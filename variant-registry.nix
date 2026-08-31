{
  lib,
  final,
  prev,
  cachyosPackages,
  dropUpdate,
}:

let
  gccVersions = builtins.fromJSON (builtins.readFile ./linux-cachyos/versions.json);

  # Static metadata table for top-level exposure and update dropping
  variantMeta = {
    gcc = {
      kernelAlias = "linux_cachyos";
      nvidiaDropUpdate = true;
    };
    lto = {
      kernelDropUpdate = true;
      nvidiaDropUpdate = true;
    };
    "lto-znver4" = {
      kernelDropUpdate = true;
      nvidiaDropUpdate = true;
    };
    lts = { };
    rc = { };
    server = { };
    hardened = { };
  };

  variantNames = builtins.attrNames variantMeta;

  # Expose linuxPackages_cachyos-* and bare linux_cachyos-* kernel derivations
  linuxKernelAttrs = builtins.listToAttrs (
    lib.concatMap (
      name:
      let
        attrs = variantMeta.${name};
        pkg = cachyosPackages."cachyos-${name}";
        kernelDrop = attrs.kernelDropUpdate or false;
        alias = attrs.kernelAlias or null;
      in
      [
        {
          name = "linuxPackages_cachyos-${name}";
          value = pkg;
        }
        {
          name = "linux_cachyos-${name}";
          value = if kernelDrop then dropUpdate pkg.kernel else pkg.kernel;
        }
      ]
      ++ lib.optionals (alias != null) [
        {
          name = "linuxPackages_cachyos";
          value = pkg;
        }
        {
          name = alias;
          # Ensure top-level alias does not duplicate updateScript
          value = dropUpdate pkg.kernel;
        }
      ]
    ) variantNames
  );

  # Expose per-flavor proprietary and open nvidia drivers
  nvidiaKernelAttrs = builtins.listToAttrs (
    lib.concatMap (
      name:
      let
        attrs = variantMeta.${name};
        pkg = cachyosPackages."cachyos-${name}";
        nvidiaDrop = attrs.nvidiaDropUpdate or false;
        drv = pkg.nvidiaPackages.cachyos;
      in
      [
        {
          name = "nvidia_cachyos-${name}";
          value = if nvidiaDrop then dropUpdate drv else drv;
        }
        {
          name = "nvidia_cachyos-${name}-open";
          value = dropUpdate drv.open;
        }
      ]
    ) variantNames
  );

  # Top-level unqualified nvidia aliases pointing to default GCC flavor
  topLevelNvidia = {
    nvidia_cachyos = cachyosPackages."cachyos-gcc".nvidiaPackages.cachyos;
    nvidia_cachyos-open = dropUpdate cachyosPackages."cachyos-gcc".nvidiaPackages.cachyos.open;
  };

  # Standalone ZFS userspace utilities matching mainline GCC flavor
  zfs = {
    zfs_cachyos = dropUpdate (
      prev.zfs_2_4.overrideAttrs (prevAttrs: {
        src = final.fetchFromGitHub {
          owner = "cachyos";
          repo = "zfs";
          inherit (gccVersions.zfs) rev hash;
        };
        patches = [ ];
        passthru = prevAttrs.passthru // {
          kernelModuleAttribute = "zfs_cachyos";
        };
        postPatch = builtins.replaceStrings [ "grep --quiet '^Linux-M" ] [ "# " ] prevAttrs.postPatch;
      })
    );
  };
in
linuxKernelAttrs // topLevelNvidia // nvidiaKernelAttrs // zfs
