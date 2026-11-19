#!/usr/bin/env bash
set -xeuo pipefail

# Compare our built kernel config against the official CachyOS package.
#
#   CACHY_FLAVOR   upstream package suffix (default: empty, i.e. linux-cachyos)
#   NYX_PKG        our attribute name (default: linux_cachyos-lto)
#   NYX_TARGET     kernel | configfile (default: kernel)
#
# Example:
#   CACHY_FLAVOR=-lts NYX_PKG=linux_cachyos-lts ./conformance-test.sh

NYX_FLAKE=${NYX_FLAKE:-$PWD}
NYX_TARGET=${NYX_TARGET:-kernel}
CACHY_FLAVOR=${CACHY_FLAVOR:-}

test -s "$NYX_FLAKE/flake.nix"

NYX_WD="${NYX_WD:-$(mktemp -d)}"
cd "$NYX_WD"
echo "Working at $NYX_WD"

# Pick the versions file matching the requested upstream flavor.
case "$CACHY_FLAVOR" in
"") VERSIONS_FILE="versions.json" ;;
*) VERSIONS_FILE="versions${CACHY_FLAVOR}.json" ;;
esac

CACHY_VERSION=${CACHY_VERSION:-$(jq -r '"\(.linux.version)-\(.linux.tagrel)"' "$NYX_FLAKE/linux-cachyos/$VERSIONS_FILE")}
CACHY_URL="https://mirror.cachyos.org/repo/x86_64${CACHY_REPO_SUFFIX:-}/cachyos/linux-cachyos${CACHY_FLAVOR}-${CACHY_VERSION}-x86_64.pkg.tar.zst"

[ -e ./linux-cachy.pkg.tar.zst ] || curl -o linux-cachy.pkg.tar.zst "$CACHY_URL"

[ -e ./linux-cachy/.PKGINFO ] || (mkdir -p linux-cachy && cd linux-cachy && tar --zstd -xf ../linux-cachy.pkg.tar.zst)

if [ "$NYX_TARGET" = 'kernel' ]; then
  nix build --out-link ./linux-ours "$NYX_FLAKE#${NYX_PKG:-linux_cachyos-lto}"
elif [ "$NYX_TARGET" = 'configfile' ]; then
  nix build --out-link ./linux-ours.kconfig "$NYX_FLAKE#${NYX_PKG:-linux_cachyos-lto}.passthru.configfile"
else
  echo 'Unsupported NYX_TARGET' >&2
  exit 1
fi

[ -n "$(find ./linux-ours-src -mindepth 2 -maxdepth 2 -name Makefile -print -quit)" ] || (
  mkdir -p linux-ours-src &&
    cd linux-ours-src &&
    tar -xzf "$(nix build --no-link --print-out-paths "$NYX_FLAKE#${NYX_PKG:-linux_cachyos}.src" | head -n 1)"
)

EXTRACTOR=$(echo ./linux-ours-src/*/scripts/extract-ikconfig)

test -e "$EXTRACTOR"

CACHY_VMLINUZ="./linux-cachy/usr/lib/modules/${CACHY_MODDIR:-$CACHY_VERSION-cachyos}/vmlinuz"
OURS_VMLINUZ="./linux-ours/bzImage"

"$EXTRACTOR" "$CACHY_VMLINUZ" | sort -u >cachy-config.txt

if [ "$NYX_TARGET" = 'kernel' ]; then
  "$EXTRACTOR" "$OURS_VMLINUZ" | sort -u >ours-config.txt
else
  sort -u linux-ours.kconfig >ours-config.txt
fi

echo 'Done, diff:'

diff -u cachy-config.txt ours-config.txt
