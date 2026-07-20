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
    moreutils
    nix
    git
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

  pkgbuild=$(curl -fsSL --connect-timeout 10 --max-time 30 \
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
    persistencedHash=$(fetch_hash_unpack "https://github.com/NVIDIA/nvidia-persistenced/archive/$latestVer.tar.gz")

    jq \
      --arg ver "$latestVer" \
      --arg main "$mainHash" \
      --arg aarch64 "$aarch64Hash" \
      --arg open "$openHash" \
      --arg settings "$settingsHash" \
      --arg persistenced "$persistencedHash" \
      '.version = $ver | .hash = $main | .aarch64Hash = $aarch64 | .openHash = $open | .settingsHash = $settings | .persistencedHash = $persistenced' \
      "$srcJson" | sponge "$srcJson"

    git add nvidia-cachyos
    git commit -m "nvidia_cachyos${suffix}: $localVer -> $latestVer"

    echo "Successfully updated $srcJson to $latestVer and committed"
  else
    echo "NVIDIA CachyOS is already up to date (Version: $localVer)"
  fi
''
