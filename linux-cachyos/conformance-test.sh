#!/usr/bin/env bash
set -xeuo pipefail

FLAKE_DIR="${FLAKE_DIR:-$PWD}"
BUILD_TARGET="${BUILD_TARGET:-kernel}"
BUILD_PKG="${BUILD_PKG:-linux_cachyos-lto}"

test -s "$FLAKE_DIR/flake.nix"

WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
cd "$WORK_DIR"
echo "Working at $WORK_DIR"

: "${CACHY_VERSION:?Set CACHY_VERSION, e.g. 7.2.2-1}"
CACHY_URL="https://mirror.cachyos.org/repo/x86_64${CACHY_REPO_SUFFIX:-}/cachyos/linux-cachyos${CACHY_FILE_SUFFIX:--$CACHY_VERSION-x86_64}.pkg.tar.zst"

# Download upstream CachyOS official binary package.
if [[ ! -e ./linux-cachy.pkg.tar.zst ]]; then
  curl -fsSL -o linux-cachy.pkg.tar.zst "$CACHY_URL"
fi

# Unpack Arch Linux package.
if [[ ! -e ./linux-cachy/.PKGINFO ]]; then
  mkdir -p linux-cachy
  (cd linux-cachy && tar --zstd -xf ../linux-cachy.pkg.tar.zst)
fi

# Build Nix target (kernel binary or configfile).
if [[ $BUILD_TARGET == "kernel" ]]; then
  nix build --out-link ./linux-cachyos "$FLAKE_DIR#${BUILD_PKG}"
elif [[ $BUILD_TARGET == "configfile" ]]; then
  nix build --out-link ./linux-cachyos.kconfig "$FLAKE_DIR#${BUILD_PKG}.passthru.configfile"
else
  echo "Unsupported BUILD_TARGET: $BUILD_TARGET" >&2
  exit 1
fi

# Fetch and unpack kernel source to obtain extract-ikconfig script.
if ! find ./linux-cachyos-src -mindepth 2 -maxdepth 2 -name Makefile -print -quit | grep -q .; then
  mkdir -p linux-cachyos-src
  (
    cd linux-cachyos-src
    tar -xzf "$(nix build --no-link --print-out-paths "$FLAKE_DIR#${BUILD_PKG}.src" | head -n 1)"
  )
fi

EXTRACTOR="$(find ./linux-cachyos-src -name extract-ikconfig -print -quit)"
test -n "$EXTRACTOR" && test -e "$EXTRACTOR"
chmod +x "$EXTRACTOR"

# Locate official CachyOS vmlinuz with fallback.
CACHY_VMLINUZ="./linux-cachy/usr/lib/modules/${CACHY_MODDIR:-$CACHY_VERSION-cachyos}/vmlinuz"
if [[ ! -f $CACHY_VMLINUZ ]]; then
  CACHY_VMLINUZ="$(find ./linux-cachy -type f \( -name vmlinuz -o -name 'vmlinuz-*' \) | head -n 1)"
fi
test -f "$CACHY_VMLINUZ"

BUILT_VMLINUZ="./linux-cachyos/bzImage"

# Extract and compare Kconfig definitions.
"$EXTRACTOR" "$CACHY_VMLINUZ" | sort -u >cachy-config.txt

if [[ $BUILD_TARGET == "kernel" ]]; then
  "$EXTRACTOR" "$BUILT_VMLINUZ" | sort -u >cachyos-config.txt
else
  sort -u linux-cachyos.kconfig >cachyos-config.txt
fi

echo 'Done, diff:'
diff -u cachy-config.txt cachyos-config.txt
