#!/usr/bin/env bash
set -eu

for flavor in cachyos{-gcc,-hardened,-lto,-lts,-rc,-server}; do
  echo "Recreating $flavor"
  out="$(nix build ".#legacyPackages.x86_64-linux.linuxPackages_${flavor}.kernel.kconfigToNix" --no-link --print-out-paths)"
  [ -s "$out" ] && cat "$out" >"linux-cachyos/config-nix/${flavor}.x86_64-linux.nix"
done

# znver4 uses a different derivation name but shares the config-nix file
echo "Recreating cachyos-lto-znver4"
out="$(nix build ".#legacyPackages.x86_64-linux.linuxPackages_cachyos-lto-znver4.kernel.kconfigToNix" --no-link --print-out-paths)"
[ -s "$out" ] && cat "$out" >"linux-cachyos/config-nix/cachyos-znver4.x86_64-linux.nix"
