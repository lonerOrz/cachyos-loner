# AGENTS.md — CachyOS-loner

Thin Nix-flake wrapper that repackages **CachyOS kernels** (`linux-cachyos/*`)
and **NVIDIA drivers** (`nvidia-cachyos/*`) on top of
[nixpkgs](https://github.com/NixOS/nixpkgs) (`nixos-unstable`). The CachyOS
files intentionally mirror nixpkgs' own kernel / NVIDIA derivations; when
nixpkgs changes those derivations, the matching CachyOS file usually needs a
matching change.

## Tech stack

- Nix + flakes; pinned nixpkgs = `nixos-unstable` (see `flake.lock`).
- CachyOS artifacts are pulled from **four GitHub repos** (below), not from
  nixpkgs and not from kernel.org.
- Current kernels ~7.1.x; NVIDIA drivers 610.x.

## Commands

```bash
nix eval --raw .#inputs.nixpkgs.outPath   # path of the nixpkgs checkout in use
nix build .#linux_cachyos-gcc.kernel       # build one kernel
nix build .#nvidia_cachyos                 # build the NVIDIA driver
nix eval .#needCacheDrvs.x86_64-linux      # list every kernel/module drv (CI cache set)
nix run .#update                           # bump versions/hashes + regenerate config snapshots
```

`nix run .#update` runs `linux-cachyos/update.nix` and `nvidia-cachyos/update.nix`,
which rewrite `versions*.json` (and `version*.json`), the config/patches/zfs
git hashes, and the generated `config-nix/*.nix` / `config-vars/*.json` snapshots.

## Project structure

| File                                                    | Role                                                                                                                          |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `flake.nix`                                             | overlay + `packages` / `legacyPackages` / `needCacheDrvs`                                                                     |
| `linux-cachyos/flavors.nix`                             | **single source of truth** for per-flavor build config (taste, configPath, cachyVars, versions, updateConfig, packagesExtend) |
| `linux-cachyos/options.nix`                             | CachyOS Kconfig flag tables; `buildPkgbuildConfig` assembles the `scripts/config` flag list                                   |
| `linux-cachyos/prepare.nix`                             | fetches kernel/patches/config/zfs; generates `.config`; `kernelPatches`; `extraVerPatch` (`EXTRAVERSION=-cachyos`)            |
| `linux-cachyos/kernel.nix`                              | calls `linuxManualConfig` (mirrors nixpkgs `build.nix`); sets `modDirVersion` / `isLTS` / `features`                          |
| `linux-cachyos/packages-for.nix`                        | builds the package set (kernel, zfs, nvidiaPackages wiring, LTO module overlay); imports nixpkgs `common-flags.nix` by path   |
| `linux-cachyos/default.nix`                             | `mapAttrs` over `flavors.nix` → the 7 flavors                                                                                 |
| `linux-cachyos/variant-registry.nix`                    | `variantMeta` table → exposes `linuxPackages_cachyos-*` / `linux_cachyos-*` / `nvidia_cachyos-*` / `zfs_cachyos`              |
| `linux-cachyos/lib/{llvm-pkgs,llvm-module-overlay}.nix` | clang/LTO stdenv + out-of-tree module overrides                                                                               |
| `nvidia-cachyos/default.nix`                            | `mkDriver` wrapper (mirrors nixpkgs `nvidia-x11/generic.nix`)                                                                 |
| `linux-cachyos/update.nix`, `nvidia-cachyos/update.nix` | version/hash bumpers                                                                                                          |

## CachyOS upstream sources (the real origins)

All `linux-cachyos` / `nvidia-cachyos` fetches come from these four repos.
`versions*.json` (one per flavor) is the single source of truth for the
rev/hash of each.

| Repo                     | Role                                                             | Consumed by                     | `versions*.json` field                          |
| ------------------------ | ---------------------------------------------------------------- | ------------------------------- | ----------------------------------------------- |
| `CachyOS/linux`          | kernel source tarball `cachyos-<ver>-<tagrel>.tar.gz`            | `prepare.nix` `src`             | `linux.version` / `linux.hash` / `linux.tagrel` |
| `CachyOS/kernel-patches` | patch queue (`all/`,`sched/`,`misc/`) keyed by `<major>.<minor>` | `prepare.nix` `patches-src`     | `patches.rev` / `patches.hash`                  |
| `CachyOS/linux-cachyos`  | per-flavor `.config` at `<taste>/config`                         | `prepare.nix` `config-src`      | `config.rev` / `config.hash`                    |
| `cachyos/zfs`            | CachyOS zfs fork at a pinned commit                              | `packages-for.nix` zfs override | `zfs.rev` / `zfs.hash`                          |

- **`tagrel` branch (kernel source):** every shipped flavor sets `tagrel`, so
  `prepare.nix` fetches the CachyOS release tarball (already sauced) and does
  NOT apply `0001-cachyos-base-all.patch`. Dropping `tagrel` would fall back to
  a mainline kernel.org tarball + the base-all patch (currently dead path).
- **Path interpolation:** `majorMinor = lib.versions.majorMinor version`
  selects `kernel-patches/<majorMinor>/…`. `taste` (per flavor, in
  `flavors.nix`) selects the upstream `.config` dir (`${config-src}/${taste}/config`)
  and, for non-LTO flavors, the nvidia suffix.
- **zfs pin:** `zfs.rev` for stable/lts/rc/server = `c681af76…` (the exact
  commit in the upstream PKGBUILD); hardened uses its own rev.
- **Generated snapshots:** `config-nix/*.nix` and `config-vars/*.json` are
  produced by `update.nix` from the upstream `.config` — never hand-edit.

### When CachyOS bumps (look here FIRST)

1. Kernel point/RC/LTS: bump `linux.{version,hash,tagrel}`, re-run `update.nix`.
2. Patchset: bump `patches.{rev,hash}`, re-run `update.nix`.
3. Flavor `.config`: bump `config.{rev,hash}`, re-run `update.nix`.
4. zfs: bump `zfs.{rev,hash}`, re-run `update.nix`.
5. A fetch 404 / hash-mismatch → the four repos above moved, not nixpkgs.

## Kernel build notes

- `modDirVersion = lib.versions.pad 3 "${version}${suffix}"` must equal the
  kernel `EXTRAVERSION`, which `prepare.nix` `extraVerPatch` appends `-cachyos`
  to (the fork tarballs ship an empty or `-rcN` `EXTRAVERSION`, so the result
  is `-cachyos` / `-rcN-cachyos`). Confirmed to match `uname -r`.
- LTO kernels use `clangStdenv`, whose `/bin/ld` _is_ `ld.lld` (see nixpkgs
  `bintools.nix`). Do **not** "fix" that — it is intentional.
- `isLTS` is currently hardcoded `false` in `kernel.nix`; harmless metadata.

## NVIDIA build notes

- **Hash contract** — `update.nix` hashes must match how nixpkgs _fetches_:
  `.run` tarballs → `fetch_hash` (file); GitHub archives → `fetch_hash_unpack`
  (unpacked). Mismatch = fetch failure at build time.

  | Field                           | nixpkgs fetch                                | `update.nix`        |
  | ------------------------------- | -------------------------------------------- | ------------------- |
  | `hash` / `aarch64Hash` (`.run`) | `generic.nix` `fetchurl` (file)              | `fetch_hash`        |
  | `openHash`                      | `kernel-modules.nix` `fetchFromGitHub {tag}` | `fetch_hash_unpack` |
  | `settingsHash`                  | `settings.nix` `fetchFromGitHub {rev}`       | `fetch_hash_unpack` |
  | `persistencedHash`              | `persistenced.nix` `fetchFromGitHub {rev}`   | `fetch_hash_unpack` |

- Our 610.x open driver has the `NV_LINUX_OF_GPIO_H_PRESENT` compat shim, so it
  builds on 7.x kernels. The `linux/of_gpio.h` hard-include error only affects
  old stock 595.x drivers (not built here).
- The LTO nvidia is wired correctly: `packages-for.nix` `addOurs` resolves a
  kernel's `nvidiaPackages.cachyos` to the **clang-built** `nvidia_cachyos-lto`
  for LTO kernels (`stdenv.cc.isClang → "-lto"`), and to the GCC-built
  `nvidia_cachyos` otherwise (suffix from `taste`).

## Boundaries

- **Never** hand-edit `config-nix/*.nix` or `config-vars/*.json`; regenerate
  with `nix run .#update`.
- **Never** edit the four upstream fetch URLs/hashes by hand; bump
  `versions*.json` and re-run `update.nix`.
- `common-flags.nix` and `generic.nix` are imported **by path** from nixpkgs;
  if nixpkgs renames them, fix the import path in `packages-for.nix` /
  `nvidia-cachyos/default.nix`.
- Don't add comments to source files unless asked (repo convention).

## When nixpkgs changes

1. `nix eval --raw .#inputs.nixpkgs.outPath` → open that checkout.
2. Kernel broke? Compare `pkgs/os-specific/linux/kernel/build.nix` +
   `common-flags.nix` against `kernel.nix` + `packages-for.nix`.
3. NVIDIA broke? Compare `pkgs/os-specific/linux/nvidia-x11/generic.nix`
   `mkDriver` args/asserts against `nvidia-cachyos/default.nix`; re-run
   `update.nix` and check the hash-contract table.
4. A module (zfs, evdi, nvidia, …) broke? Its nixpkgs source is under
   `pkgs/os-specific/linux/<name>`; our wrapper is in `packages-for.nix`
   `addOurs` / `lib/llvm-module-overlay.nix`.

## Commits

Conventional-ish prefixes already in use (`fix:`, `refactor:`, `linux_cachyos-*:`,
`ci:`); keep them. Keep this file lean — prefer restructuring over appending.
