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

  suffix = if variant == "stable" || variant == "lto" then "" else "-${variant}";
in
writeShellScriptBin "update-nvidia-cachyos-${variant}" ''
  set -euo pipefail
  PATH=${path}

  srcJson="nvidia-cachyos/version${suffix}.json"

  if [[ ! -f "$srcJson" ]]; then
    mkdir -p "$(dirname "$srcJson")"
    echo "{}" > "$srcJson"
  fi

  pkgbuild=$(curl -fsSL --http1.1 --connect-timeout 10 --max-time 30 \
    "https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos${suffix}/PKGBUILD")
  latestVer=$(echo "$pkgbuild" | grep -Po '(?<=_nv_ver=)([^[:space:]]+)')

  localVer=$(jq -r '.version // ""' < "$srcJson")
  mainHash=$(jq -r '.hash // ""' < "$srcJson")
  aarch64Hash=$(jq -r '.aarch64Hash // ""' < "$srcJson")
  openHash=$(jq -r '.openHash // ""' < "$srcJson")
  settingsHash=$(jq -r '.settingsHash // ""' < "$srcJson")
  persistencedHash=$(jq -r '.persistencedHash // ""' < "$srcJson")

  versionChanged=false

  if [[ "$localVer" != "$latestVer" ]]; then
    echo "NVIDIA Version changed: $localVer -> $latestVer"
    versionChanged=true
  fi

  # Extract kernel major version for patch discovery
  kernelMajor=$(echo "$pkgbuild" | grep -Po '(?<=_major=)([^[:space:]]+)')
  echo "Kernel major version: $kernelMajor"

  fetch_hash() {
    nix-prefetch-url "$1" | xargs nix-hash --to-sri --type sha256
  }

  fetch_hash_unpack() {
    nix-prefetch-url --unpack "$1" | xargs nix-hash --to-sri --type sha256
  }

  fetchpatch_hash() {
    local url="$1"
    local tmp
    tmp=$(mktemp)
    curl -fsSL --http1.1 --connect-timeout 10 --max-time 30 "$url" -o "$tmp"
    # Raw file hash — matches fetchurl in default.nix (no normalization)
    nix-hash --flat --type sha256 "$tmp" | xargs nix-hash --to-sri --type sha256
    rm -f "$tmp"
  }

  # Parse nvidia patches from PKGBUILD source array — only patches that
  # CachyOS actually applies to the open driver, not all files in the dir.
  discover_kernel_patches() {
    local major="$1"
    local pkgbuild_content="$2"

    local patches_json="[]"
    while IFS= read -r patch_name; do
      local url hash
      url="https://raw.githubusercontent.com/CachyOS/kernel-patches/master/$major/misc/nvidia/$patch_name"
      hash=$(fetchpatch_hash "$url")
      patches_json=$(echo "$patches_json" | jq \
        --arg n "$patch_name" --arg u "$url" --arg h "$hash" \
        '. + [{"name": $n, "url": $u, "hash": $h}]')
    done < <(echo "$pkgbuild_content" | grep -oP "misc/nvidia/\\K[^\"'\\s]+\\.patch" | sort -u)

    echo "$patches_json"
  }

  changed=false

  if [[ "$versionChanged" == "true" ]]; then
    echo "Fetching hashes for new version $latestVer..."
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

  # Always re-discover kernel patches (they can change independently of driver version)
  echo "Discovering kernel patches for major $kernelMajor..."
  kernelPatches=$(discover_kernel_patches "$kernelMajor" "$pkgbuild")
  patchCount=$(echo "$kernelPatches" | jq 'length')
  echo "Final kernel patches: $patchCount"

  oldPatches=$(jq -c '.kernelPatches // []' < "$srcJson")
  newPatches=$(echo "$kernelPatches" | jq -c '.')
  if [[ "$oldPatches" != "$newPatches" ]]; then
    jq --argjson kp "$kernelPatches" '.kernelPatches = $kp' "$srcJson" > "$srcJson.tmp" && mv "$srcJson.tmp" "$srcJson"
    changed=true
  fi

  if [[ "$changed" == "true" ]]; then
    git add nvidia-cachyos
    git commit -m "nvidia_cachyos${suffix}: update versions and kernel patches"
    echo "Successfully updated $srcJson"
  else
    echo "NVIDIA CachyOS is already up to date (Version: $localVer)"
  fi
''
