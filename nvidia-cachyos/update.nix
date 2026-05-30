{
  writeShellScriptBin,
  lib,
  coreutils,
  findutils,
  curl,
  gnugrep,
  jq,
  nix,
  moreutils,
  variant,
}:

let
  path = lib.makeBinPath [
    coreutils
    findutils
    curl
    gnugrep
    jq
    moreutils
    nix
  ];

  suffix = if variant == "stable" then "" else "-${variant}";
in
writeShellScriptBin "update-nvidia-cachyos-${variant}" ''
  set -euo pipefail
  PATH=${path}

  srcJson="nvidia-cachyos/version${suffix}.json"

  if [[ ! -f "$srcJson" ]]; then
    mkdir -p "$(dirname "$srcJson")"
    echo "{}" > "$srcJson"
  fi

  pkgbuild=$(curl -fsSL "https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos${suffix}/PKGBUILD")
  latestVer=$(echo "$pkgbuild" | grep -Po '(?<=_nv_ver=)([^[:space:]]+)')
  major=$(echo "$pkgbuild" | grep -Po '(?<=^_major=)[0-9.]+')

  localVer=$(jq -r '.version // ""' < "$srcJson")
  localMajor=$(jq -r '.major // ""' < "$srcJson")
  mainHash=$(jq -r '.hash // ""' < "$srcJson")
  aarch64Hash=$(jq -r '.aarch64Hash // ""' < "$srcJson")
  openHash=$(jq -r '.openHash // ""' < "$srcJson")
  settingsHash=$(jq -r '.settingsHash // ""' < "$srcJson")
  persistencedHash=$(jq -r '.persistencedHash // ""' < "$srcJson")
  localPatches=$(jq -c '.patches // []' < "$srcJson")

  versionChanged=false
  patchesChanged=false

  if [[ "$localVer" != "$latestVer" || "$localMajor" != "$major" ]]; then
    echo "Version changed: $localVer -> $latestVer"
    versionChanged=true
  fi

  fetch_hash() {
    nix-prefetch-url "$1" | xargs nix-hash --to-sri --type sha256
  }

  fetch_hash_unpack() {
    nix-prefetch-url --unpack "$1" | xargs nix-hash --to-sri --type sha256
  }

  if [[ "$versionChanged" == "true" ]]; then
    echo "Fetching hashes for new version $latestVer..."
    mainHash=$(fetch_hash "https://download.nvidia.com/XFree86/Linux-x86_64/$latestVer/NVIDIA-Linux-x86_64-$latestVer.run")
    aarch64Hash=$(fetch_hash "https://download.nvidia.com/XFree86/Linux-aarch64/$latestVer/NVIDIA-Linux-aarch64-$latestVer.run")
    openHash=$(fetch_hash_unpack "https://github.com/NVIDIA/open-gpu-kernel-modules/archive/$latestVer.tar.gz")
    settingsHash=$(fetch_hash_unpack "https://github.com/NVIDIA/nvidia-settings/archive/$latestVer.tar.gz")
    persistencedHash=$(fetch_hash "https://download.nvidia.com/XFree86/nvidia-persistenced/nvidia-persistenced-$latestVer.tar.bz2")
  fi

  newPatchesJson="[]"
  if [[ -n "$major" ]]; then
    echo "Checking patches for major version $major..."
    patches_json=$(curl -fsSL "https://api.github.com/repos/cachyos/kernel-patches/contents/$major/misc/nvidia" 2>/dev/null) || patches_json=""

    if [[ -n "$patches_json" ]]; then
      new_patches=$(
        echo "$patches_json" \
        | jq -r '.[] | select(.name | endswith(".patch")) | .name' \
        | sort \
        | while read -r name; do
            url="https://raw.githubusercontent.com/cachyos/kernel-patches/master/$major/misc/nvidia/$name"
            hash=$(fetch_hash "$url")
            jq -nc --arg name "$name" --arg hash "$hash" '{name: $name, hash: $hash}'
          done \
        | jq -s '. | sort_by(.name)'
      )

      if [[ -z "$new_patches" ]]; then
        new_patches="[]"
      fi

      newPatchesStr=$(echo "$new_patches" | jq -c .)
      localPatchesStr=$(echo "$localPatches" | jq -c .)

      if [[ "$newPatchesStr" != "$localPatchesStr" ]]; then
        echo "Patches changed"
        patchesChanged=true
        newPatchesJson="$new_patches"
      else
        newPatchesJson="$localPatches"
      fi
    else
      echo "Warning: Could not fetch patch list from GitHub API or directory does not exist"
      newPatchesJson="$localPatches"
    fi
  else
    newPatchesJson="$localPatches"
  fi

  if [[ "$versionChanged" == "true" || "$patchesChanged" == "true" ]]; then
    jq \
      --arg ver "$latestVer" \
      --arg major "$major" \
      --arg main "$mainHash" \
      --arg aarch64 "$aarch64Hash" \
      --arg open "$openHash" \
      --arg settings "$settingsHash" \
      --arg persistenced "$persistencedHash" \
      --argjson patches "$newPatchesJson" \
      '.version = $ver | .major = $major | .hash = $main | .aarch64Hash = $aarch64 | .openHash = $open | .settingsHash = $settings | .persistencedHash = $persistenced | .patches = $patches' \
      "$srcJson" | sponge "$srcJson"

    echo "Successfully updated $srcJson (Version: $latestVer, Major: $major)"
  else
    echo "NVIDIA CachyOS is already up to date (Version: $localVer, Patches unchanged)"
  fi
''
