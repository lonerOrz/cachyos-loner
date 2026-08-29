{
  writeShellScriptBin,
  lib,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  curl,
  jq,
  git,
  nix,
  nix-prefetch-git,
  moreutils,
  updateConfig,
}:

let
  inherit (updateConfig) versionsFile suffix flavors;
  flavorsStr = lib.concatStringsSep " " flavors;

  path = lib.makeBinPath [
    coreutils
    curl
    findutils
    gnugrep
    gnused
    gawk
    jq
    moreutils
    git
    nix-prefetch-git
    nix
  ];
in

writeShellScriptBin "update-cachyos" ''

  set -euo pipefail
  PATH=${path}

  srcJson="linux-cachyos/${versionsFile}"

  localVer=$(jq -r .linux.version < "$srcJson")
  localTagrel=$(jq -r '.linux.tagrel // -1' < "$srcJson")

  # Fetch upstream CachyOS kernel PKGBUILD.
  fetch_pkgbuild() {
    curl -fsSL --http1.1 --connect-timeout 10 --max-time 30 \
      "https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos${suffix}/PKGBUILD"
  }

  # Parse version components and construct release source tag.
  parse_all() {
    awk -F= '
      /^[[:space:]]*_major[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); major=$2 }
      /^[[:space:]]*_minor[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); minor=$2 }
      /^[[:space:]]*_rcver[[:space:]]*=/  { gsub(/[[:space:]]/, "", $2); rcver=$2 }
      /^[[:space:]]*_ltsver[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); ltsver=$2 }
      /^[[:space:]]*_tagrel[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); tagrel=$2 }
      END {
        if (rcver != "") {
          version = major "-" rcver
          srctag = "cachyos-" major "-" rcver "-" tagrel
        } else if (ltsver != "") {
          version = major "." ltsver
          srctag = "cachyos-" major "." ltsver "-" tagrel
        } else {
          version = major "." minor
          srctag = "cachyos-" major "." minor "-" tagrel
        }
        print version " " tagrel " " srctag
      }
    '
  }

  pkgbuild=$(fetch_pkgbuild)
  read -r latestVer latestTagrel srcTag < <(parse_all <<< "$pkgbuild")

  if [[ -z "$latestVer" || -z "$latestTagrel" ]]; then
    echo "ERROR: Failed to parse kernel version from upstream PKGBUILD" >&2
    exit 1
  fi

  srcUrl="https://github.com/CachyOS/linux/releases/download/''${srcTag}/''${srcTag}.tar.gz"

  # Exit early if version has not changed.
  if [[ "''${FORCE:-0}" != "1" && "$localVer" == "$latestVer" && "$localTagrel" == "$latestTagrel" ]]; then
    echo "Already up to date: $latestVer-$latestTagrel"
    exit 0
  fi

  echo "Updating: $localVer-$localTagrel -> $latestVer-$latestTagrel"

  # 1. Prefetch kernel source tarball.
  latestHash=$(nix-prefetch-url --type sha256 "$srcUrl" \
    | xargs nix-hash --to-sri --type sha256)

  prefetch_git() {
    nix-prefetch-git --quiet "$@" | jq -r '.rev + " " + .hash'
  }

  # 2. Prefetch linux-cachyos config repo in a single pass.
  configJson=$(nix-prefetch-git --quiet https://github.com/CachyOS/linux-cachyos.git)
  configRev=$(jq -r .rev <<< "$configJson")
  configHash=$(jq -r .hash <<< "$configJson")
  configPath=$(jq -r .path <<< "$configJson")

  # 3. Prefetch kernel patches repo.
  read rev hash < <(prefetch_git https://github.com/CachyOS/kernel-patches.git)
  patchesRev=$rev
  patchesHash=$hash

  # 4. Extract and prefetch paired ZFS commit.
  zfsRev=$(grep -Po "(?<=zfs.git#commit=)[^\"'\\s]+" \
    "$configPath/linux-cachyos${suffix}/PKGBUILD" || true)

  if [[ -n "$zfsRev" ]]; then
    read _ zfsHash < <(prefetch_git https://github.com/CachyOS/zfs.git --rev "$zfsRev")
  else
    echo "WARNING: zfs commit pin not found in PKGBUILD; preserving existing pin" >&2
    zfsRev=$(jq -r .zfs.rev < "$srcJson")
    zfsHash=$(jq -r .zfs.hash < "$srcJson")
  fi

  # Update versions JSON atomically.
  jq \
    --arg latestVer "$latestVer" \
    --arg latestHash "$latestHash" \
    --argjson latestTagrel "$latestTagrel" \
    --arg configRev "$configRev" \
    --arg configHash "$configHash" \
    --arg patchesRev "$patchesRev" \
    --arg patchesHash "$patchesHash" \
    --arg zfsRev "$zfsRev" \
    --arg zfsHash "$zfsHash" '
      .linux.version = $latestVer |
      .linux.hash = $latestHash |
      .linux.tagrel = $latestTagrel |
      .config.rev = $configRev |
      .config.hash = $configHash |
      .patches.rev = $patchesRev |
      .patches.hash = $patchesHash |
      .zfs.rev = $zfsRev |
      .zfs.hash = $zfsHash
    ' "$srcJson" | sponge "$srcJson"

  # Regenerate static config-nix snapshots.
  failed_flavors=()
  for flv in ${flavorsStr}; do
    out=$(nix build \
      ".#packages.x86_64-linux.linux_cachyos''${flv}.kconfigToNix" \
      --no-link --print-out-paths) && build_rc=0 || build_rc=$?

    if [ "$build_rc" -ne 0 ] || [ -z "$out" ] || [ ! -f "$out" ]; then
      echo "WARNING: kconfigToNix build failed for ''${flv} (exit=$build_rc)" >&2
      failed_flavors+=("$flv")
      continue
    fi

    cat "$out" > linux-cachyos/config-nix/cachyos''${flv}.x86_64-linux.nix
  done

  if [ ''${#failed_flavors[@]} -gt 0 ]; then
    echo "ERROR: kconfigToNix failed for: ''${failed_flavors[*]}" >&2
    echo "The kernel version was updated but config-nix snapshots are stale." >&2
    exit 1
  fi

  git add linux-cachyos
  git commit -m "linux_cachyos${suffix}: $localVer-$localTagrel -> $latestVer-$latestTagrel"
''
