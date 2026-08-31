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

  # Parse commit flag from arguments
  doCommit=false
  for arg in "$@"; do
    if [[ "$arg" == "--commit" ]]; then
      doCommit=true
    fi
  done

  srcJson="linux-cachyos/${versionsFile}"

  localVer=$(jq -r '.linux.version // ""' < "$srcJson")
  localTagrel=$(jq -r '.linux.tagrel // -1' < "$srcJson")

  # Fetch upstream CachyOS kernel PKGBUILD
  fetch_pkgbuild() {
    curl -fsSL --http1.1 --retry 3 --connect-timeout 10 --max-time 30 \
      "https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos${suffix}/PKGBUILD"
  }

  # Parse version components and construct release source tag
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

  # Check if config snapshots are missing
  missingConfigs=false
  for flv in ${flavorsStr}; do
    if [[ ! -s "linux-cachyos/config-nix/cachyos''${flv}.x86_64-linux.nix" ]]; then
      missingConfigs=true
      break
    fi
  done

  # Exit early if up to date unless FORCE=1 or config files missing
  if [[ "''${FORCE:-0}" != "1" && "$missingConfigs" == "false" && "$localVer" == "$latestVer" && "$localTagrel" == "$latestTagrel" ]]; then
    echo "Already up to date: $latestVer-$latestTagrel"
    exit 0
  fi

  echo "Updating: $localVer-$localTagrel -> $latestVer-$latestTagrel"

  # Robust download hash helper fallback to curl --http1.1
  fetch_tarball_hash() {
    local url="$1"
    local raw_hash=""
    if raw_hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null); then
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

  prefetch_git() {
    nix-prefetch-git --quiet "$@" | jq -r '.rev + " " + .hash'
  }

  # 1. Prefetch kernel source tarball
  latestHash=$(fetch_tarball_hash "$srcUrl")

  # 2. Prefetch linux-cachyos config repository
  configJson=$(nix-prefetch-git --quiet https://github.com/CachyOS/linux-cachyos.git)
  configRev=$(jq -r .rev <<< "$configJson")
  configHash=$(jq -r .hash <<< "$configJson")
  configPath=$(jq -r .path <<< "$configJson")

  # 3. Prefetch kernel patches repository
  read rev hash < <(prefetch_git https://github.com/CachyOS/kernel-patches.git)
  patchesRev=$rev
  patchesHash=$hash

  # 4. Extract and prefetch paired ZFS commit
  zfsRev=$(grep -Po "(?<=zfs.git#commit=)[^\"'\\s]+" \
    "$configPath/linux-cachyos${suffix}/PKGBUILD" || true)

  if [[ -n "$zfsRev" ]]; then
    read _ zfsHash < <(prefetch_git https://github.com/CachyOS/zfs.git --rev "$zfsRev")
  else
    echo "WARNING: zfs commit pin not found in PKGBUILD; preserving existing pin" >&2
    zfsRev=$(jq -r .zfs.rev < "$srcJson")
    zfsHash=$(jq -r .zfs.hash < "$srcJson")
  fi

  origJson=$(cat "$srcJson")

  # Update versions JSON in workspace for nix build evaluation
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

  # 5. Regenerate static config-nix snapshots
  failed_flavors=()
  for flv in ${flavorsStr}; do
    echo "Building kconfigToNix for flavor: ''${flv}..."
    out_path=""
    if out=$(nix build \
      ".#packages.x86_64-linux.linux_cachyos''${flv}.kconfigToNix" \
      --no-link --print-out-paths --impure -L 2>&1); then
      out_path=$(echo "$out" | tail -n 1)
    fi

    if [[ -n "$out_path" && -s "$out_path" ]]; then
      mkdir -p linux-cachyos/config-nix
      cat "$out_path" > "linux-cachyos/config-nix/cachyos''${flv}.x86_64-linux.nix"
      echo "Successfully updated config-nix for ''${flv}"
    else
      echo "ERROR: kconfigToNix build failed for ''${flv}:" >&2
      echo "$out" >&2
      failed_flavors+=("$flv")
    fi
  done

  # Rollback versions JSON on failure
  if [[ ''${#failed_flavors[@]} -gt 0 ]]; then
    echo "ERROR: kconfigToNix failed for: ''${failed_flavors[*]}" >&2
    echo "$origJson" > "$srcJson"
    exit 1
  fi

  # Only commit if explicitly requested
  if [[ "$doCommit" == "true" ]]; then
    git add linux-cachyos
    git commit -m "linux_cachyos${suffix}: $localVer-$localTagrel -> $latestVer-$latestTagrel"
  fi
''
