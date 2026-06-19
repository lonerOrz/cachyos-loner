#!/usr/bin/env bash
set -xeuo pipefail

FLAKE_DIR=${FLAKE_DIR:-$PWD}
BUILD_TARGET=${BUILD_TARGET:-kernel}

test -s "$FLAKE_DIR/flake.nix"

WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
cd "$WORK_DIR"
echo "Working at $WORK_DIR"

CACHY_VERSION=${CACHY_VERSION:-7.0.11-1}
CACHY_URL="https://mirror.cachyos.org/repo/x86_64${CACHY_REPO_SUFFIX:-}/cachyos/linux-cachyos${CACHY_FILE_SUFFIX:--$CACHY_VERSION-x86_64}.pkg.tar.zst"

[ -e ./linux-cachy.pkg.tar.zst ] || curl -o linux-cachy.pkg.tar.zst "$CACHY_URL"

[ -e ./linux-cachy/.PKGINFO ] || (mkdir -p linux-cachy && cd linux-cachy && tar --zstd -xf ../linux-cachy.pkg.tar.zst)

if [ "$BUILD_TARGET" = 'kernel' ]; then
  nix build --out-link ./linux-cachyos "$FLAKE_DIR#${BUILD_PKG:-linux_cachyos-lto}"
elif [ "$BUILD_TARGET" = 'configfile' ]; then
  nix build --out-link ./linux-cachyos.kconfig "$FLAKE_DIR#${BUILD_PKG:-linux_cachyos-lto}.passthru.configfile"
else
  echo 'Unsupported BUILD_TARGET' >&2
  exit 1
fi

[ -n "$(find ./linux-cachyos-src -mindepth 2 -maxdepth 2 -name Makefile -print -quit)" ] || (
  mkdir -p linux-cachyos-src &&
    cd linux-cachyos-src &&
    tar -xzf "$(nix build --no-link --print-out-paths "$FLAKE_DIR#${BUILD_PKG:-linux_cachyos}.src" | head -n 1)"
)

EXTRACTOR=$(echo ./linux-cachyos-src/*/scripts/extract-ikconfig)

test -e "$EXTRACTOR"

CACHY_VMLINUZ="./linux-cachy/usr/lib/modules/${CACHY_MODDIR:-$CACHY_VERSION-cachyos}/vmlinuz"
BUILT_VMLINUZ="./linux-cachyos/bzImage"

"$EXTRACTOR" "$CACHY_VMLINUZ" | sort -u >cachy-config.txt

if [ "$BUILD_TARGET" = 'kernel' ]; then
  "$EXTRACTOR" "$BUILT_VMLINUZ" | sort -u >cachyos-config.txt
else
  sort -u linux-cachyos.kconfig >cachyos-config.txt
fi

echo 'Done, diff:'

diff -u cachy-config.txt cachyos-config.txt
