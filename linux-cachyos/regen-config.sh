#!/usr/bin/env bash
set -eu

for flavor in cachyos{-gcc,-hardened,-lto,-lts,-rc,-server}; do
  echo "Recreating $flavor"
  out="$(nix build ".#packages.x86_64-linux.linux_cachyos-${flavor}.kconfigToNix" --no-link --print-out-paths)"
  [ -s "$out" ] && cat "$out" >"linux-cachyos/config-nix/${flavor}.x86_64-linux.nix"
done

# znver4 uses a different derivation name but shares the config-nix file
echo "Recreating cachyos-lto-znver4"
out="$(nix build ".#packages.x86_64-linux.linux_cachyos-lto-znver4.kconfigToNix" --no-link --print-out-paths)"
[ -s "$out" ] && cat "$out" >"linux-cachyos/config-nix/cachyos-znver4.x86_64-linux.nix"
