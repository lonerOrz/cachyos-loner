#!/usr/bin/env bash
set -euo pipefail

# Resolve repository root directory regardless of invocation path.
REPO_ROOT="$(cd "$(dirname "''${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Regenerate standard flavor snapshots.
for flavor in gcc hardened lto lts rc server; do
  echo "Recreating config-nix for flavor: $flavor"
  out="$(nix build ".#packages.x86_64-linux.linux_cachyos-${flavor}.kconfigToNix" --no-link --print-out-paths)"
  if [[ -s "$out" ]]; then
    cat "$out" >"linux-cachyos/config-nix/cachyos-${flavor}.x86_64-linux.nix"
  fi
done

echo "Successfully regenerated all config-nix snapshots."
