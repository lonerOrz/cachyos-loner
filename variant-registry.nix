{
  lib,
  final,
  prev,
  cachyosPackages,
  callOverride,
  dropUpdate,
}:

let
  # Single source of truth for per-variant exposure metadata.
  # kernelAlias/nvidiaDropUpdate/kernelDropUpdate drive the linuxPackages_cachyos-* exposure;
  # nvidiaVariant drives the paired nvidia_cachyos-* package.
  variantMeta = {
    gcc = {
      nvidiaVariant = "stable";
      kernelAlias = "linux_cachyos";
      nvidiaDropUpdate = true;
    };
    lto = {
      nvidiaVariant = "lto";
      kernelDropUpdate = true;
      nvidiaDropUpdate = true;
    };
    "lto-znver4" = {
      nvidiaVariant = "lto";
      kernelDropUpdate = true;
      nvidiaDropUpdate = true;
    };
    lts = {
      nvidiaVariant = "lts";
    };
    rc = {
      nvidiaVariant = "rc";
    };
    server = {
      nvidiaVariant = "server";
    };
    hardened = {
      nvidiaVariant = "hardened";
    };
  };

  variantNames = builtins.attrNames variantMeta;

  linuxKernelAttrs = builtins.listToAttrs (
    lib.concatMap (
      name:
      let
        attrs = variantMeta.${name};
        pkg = cachyosPackages."cachyos-${name}";
      in
      [
        {
          name = "linuxPackages_cachyos-${name}";
          value = pkg;
        }
        {
          name = "linux_cachyos-${name}";
          value = if attrs ? kernelDropUpdate then dropUpdate pkg.kernel else pkg.kernel;
        }
      ]
      ++ lib.optionals (attrs ? kernelAlias) [
        {
          name = "linuxPackages_cachyos";
          value = pkg;
        }
        {
          name = attrs.kernelAlias;
          value = if attrs ? kernelDropUpdate then dropUpdate pkg.kernel else pkg.kernel;
        }
      ]
    ) variantNames
  );

  nvidiaKernelAttrs = builtins.listToAttrs (
    lib.concatMap (
      name:
      let
        meta = variantMeta.${name};
        pkg = cachyosPackages."cachyos-${name}";
        variantArg = {
          variant = meta.nvidiaVariant;
        };
      in
      [
        {
          name = "nvidia_cachyos-${name}";
          value =
            let
              drv = callOverride ./nvidia-cachyos (variantArg // { linuxPackages = pkg; });
            in
            if meta ? nvidiaDropUpdate then dropUpdate drv else drv;
        }
        {
          name = "nvidia_cachyos-${name}-open";
          value = dropUpdate (callOverride ./nvidia-cachyos (variantArg // { linuxPackages = pkg; })).open;
        }
      ]
    ) variantNames
  );

  topLevelNvidia = {
    nvidia_cachyos = callOverride ./nvidia-cachyos { linuxPackages = cachyosPackages."cachyos-gcc"; };
    nvidia_cachyos-open =
      dropUpdate
        (callOverride ./nvidia-cachyos { linuxPackages = cachyosPackages."cachyos-gcc"; }).open;
  };

  zfs = {
    zfs_cachyos = dropUpdate (
      prev.zfs_2_4.overrideAttrs (prevAttrs: {
        src = cachyosPackages."cachyos-gcc".zfs_cachyos.src;
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
