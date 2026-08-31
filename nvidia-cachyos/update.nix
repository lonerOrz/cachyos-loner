{
  writeShellScriptBin,
  lib,
  coreutils,
  findutils,
  curl,
  gnugrep,
  jq,
  nix,
  git,
  variant,
}:

let
  path = lib.makeBinPath [
    coreutils
    findutils
    curl
    gnugrep
    jq
    nix
    git
  ];

  # Map variant to local JSON and upstream PKGBUILD suffix
  suffix = if variant == "stable" then "" else "-${variant}";
in
writeShellScriptBin "update-nvidia-cachyos-${variant}" ''

  set -euo pipefail
  PATH=${path}

  # Parse commit flag from arguments
  doCommit=false
  for arg in "$@"; do
    if [[ "$arg" == "--commit" ]]; then
      doCommit=true
    fi
  done

  srcJson="nvidia-cachyos/version${suffix}.json"

  if [[ ! -f "$srcJson" ]]; then
    mkdir -p "$(dirname "$srcJson")"
    echo "{}" > "$srcJson"
  fi

  # Fetch upstream PKGBUILD
  pkgbuild=$(curl -fsSL --http1.1 --retry 3 --connect-timeout 10 --max-time 30 \
    "https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos${suffix}/PKGBUILD")
  latestVer=$(echo "$pkgbuild" | grep -Po '(?<=_nv_ver=)([^[:space:]]+)')

  if [[ -z "$latestVer" ]]; then
    echo "ERROR: Could not parse _nv_ver from upstream PKGBUILD" >&2
    exit 1
  fi

  localVer=$(jq -r '.version // ""' < "$srcJson")
  mainHash=$(jq -r '.hash // ""' < "$srcJson")
  aarch64Hash=$(jq -r '.aarch64Hash // ""' < "$srcJson")
  openHash=$(jq -r '.openHash // ""' < "$srcJson")
  settingsHash=$(jq -r '.settingsHash // ""' < "$srcJson")
  persistencedHash=$(jq -r '.persistencedHash // ""' < "$srcJson")

  versionChanged=false
  if [[ "''${FORCE:-0}" == "1" || "$localVer" != "$latestVer" || -z "$mainHash" ]]; then
    echo "NVIDIA Version update required: $localVer -> $latestVer"
    versionChanged=true
  fi

  # Extract kernel major version for patch discovery
  kernelMajor=$(echo "$pkgbuild" | grep -Po '(?<=_major=)([^[:space:]]+)')
  if [[ -z "$kernelMajor" ]]; then
    echo "ERROR: Could not parse _major from upstream PKGBUILD" >&2
    exit 1
  fi
  echo "Kernel major version: $kernelMajor"

  # Hash fetch helpers complying with Nixpkgs fetch contracts
  fetch_hash() {
    local url="$1"
    local raw_hash=""
    if raw_hash=$(nix-prefetch-url "$url" 2>/dev/null); then
      nix-hash --to-sri --type sha256 "$raw_hash"
    else
      local tmp
      tmp=$(mktemp)
      curl -fsSL --http1.1 --retry 3 --connect-timeout 15 --max-time 300 "$url" -o "$tmp"
      raw_hash=$(nix-hash --flat --type sha256 "$tmp")
      rm -f "$tmp"
      nix-hash --to-sri --type sha256 "$raw_hash"
    fi
  }

  fetch_hash_unpack() {
    nix-prefetch-url --unpack "$1" | xargs nix-hash --to-sri --type sha256
  }

  fetchpatch_hash() {
    local url="$1"
    local tmp
    tmp=$(mktemp)
    if curl -fsSL --http1.1 --retry 3 --connect-timeout 10 --max-time 30 "$url" -o "$tmp"; then
      nix-hash --flat --type sha256 "$tmp" | xargs nix-hash --to-sri --type sha256
      rm -f "$tmp"
    else
      rm -f "$tmp"
      return 1
    fi
  }

  # Discover nvidia open driver patches listed in PKGBUILD
  discover_kernel_patches() {
    local major="$1"
    local pkgbuild_content="$2"

    local patch_names
    patch_names=$(echo "$pkgbuild_content" | grep -oP "misc/nvidia/\\K[^\"'\\s]+\\.patch" | sort -u || true)

    if [[ -z "$patch_names" ]]; then
      echo "[]"
      return 0
    fi

    local patches_json="[]"
    while IFS= read -r patch_name; do
      [[ -z "$patch_name" ]] && continue
      local url hash
      url="https://raw.githubusercontent.com/CachyOS/kernel-patches/master/$major/misc/nvidia/$patch_name"
      if ! hash=$(fetchpatch_hash "$url"); then
        echo "ERROR: Failed to fetch patch $patch_name from $url" >&2
        return 1
      fi
      patches_json=$(echo "$patches_json" | jq \
        --arg n "$patch_name" --arg u "$url" --arg h "$hash" \
        '. + [{"name": $n, "url": $u, "hash": $h}]')
    done <<< "$patch_names"

    echo "$patches_json"
  }

  changed=false

  # Update driver version and hashes when version changes
  if [[ "$versionChanged" == "true" ]]; then
    echo "Fetching hashes for version $latestVer..."
    mainHash=$(fetch_hash "https://download.nvidia.com/XFree86/Linux-x86_64/$latestVer/NVIDIA-Linux-x86_64-$latestVer.run")
    aarch64Hash=$(fetch_hash "https://download.nvidia.com/XFree86/Linux-aarch64/$latestVer/NVIDIA-Linux-aarch64-$latestVer.run")
    openHash=$(fetch_hash_unpack "https://github.com/NVIDIA/open-gpu-kernel-modules/archive/$latestVer.tar.gz")
    settingsHash=$(fetch_hash_unpack "https://github.com/NVIDIA/nvidia-settings/archive/$latestVer.tar.gz")
    persistencedHash=$(fetch_hash_unpack "https://github.com/NVIDIA/nvidia-persistenced/archive/$latestVer.tar.gz")

    jq \
      --arg ver "$latestVer" \
      --arg main "$mainHash" \
      --arg aarch64 "$aarch64Hash" \
      --arg open "$openHash" \
      --arg settings "$settingsHash" \
      --arg persistenced "$persistencedHash" \
      '.version = $ver | .hash = $main | .aarch64Hash = $aarch64 | .openHash = $open | .settingsHash = $settings | .persistencedHash = $persistenced' \
      "$srcJson" > "$srcJson.tmp" && mv "$srcJson.tmp" "$srcJson"
    changed=true
  fi

  # Discover kernel patches safely without silent wipe
  echo "Discovering kernel patches for major $kernelMajor..."
  if kernelPatches=$(discover_kernel_patches "$kernelMajor" "$pkgbuild"); then
    patchCount=$(echo "$kernelPatches" | jq 'length')
    echo "Final kernel patches: $patchCount"

    oldPatches=$(jq -c '.kernelPatches // []' < "$srcJson")
    newPatches=$(echo "$kernelPatches" | jq -c '.')
    if [[ "$oldPatches" != "$newPatches" ]]; then
      jq --argjson kp "$kernelPatches" '.kernelPatches = $kp' "$srcJson" > "$srcJson.tmp" && mv "$srcJson.tmp" "$srcJson"
      changed=true
    fi
  else
    echo "WARNING: Patch discovery failed; preserving existing patches in $srcJson" >&2
  fi

  # Only commit if explicitly requested
  if [[ "$changed" == "true" ]]; then
    if [[ "$doCommit" == "true" ]]; then
      git add nvidia-cachyos
      git commit -m "nvidia_cachyos${suffix}: update versions and kernel patches"
    fi
    echo "Successfully updated $srcJson"
  else
    echo "NVIDIA CachyOS is already up to date (Version: $localVer)"
  fi
''
