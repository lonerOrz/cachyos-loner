#!/usr/bin/env bash
set -eu

# Regenerate config-nix snapshots for every flavor that has its own snapshot.
# znver4 is intentionally excluded: cachyos-znver4.x86_64-linux.nix is a
# wrapper (removeAttrs over the LTO snapshot + CONFIG_MZEN4=y), so regenerating
# it standalone would overwrite that logic with a flat config.
#
# Set NIX_OFFLINE=1 to skip substituter lookups (useful when the network is
# blocked but every build input is already in the store).

nixArgs=(--no-link --print-out-paths)
[ "${NIX_OFFLINE:-0}" = "1" ] && nixArgs+=(--offline)

for flavor in gcc hardened lto lts rc server; do
  echo "Recreating $flavor"
  out="$(nix build ".#linux_cachyos-${flavor}.kconfigToNix" "${nixArgs[@]}")"
  if [ -s "$out" ]; then
    cat "$out" >"linux-cachyos/config-nix/cachyos-${flavor}.x86_64-linux.nix"
  fi
done
