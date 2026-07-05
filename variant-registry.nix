{
  lib,
  final,
  prev,
  cachyosPackages,
  callOverride,
  dropUpdate,
}:

let
  # Overlay attribute modifiers per variant
  overlayAttrs = {
    gcc = {
      kernelAlias = "linux_cachyos";
      nvidiaDropUpdate = true;
    };
    lto = {
      kernelDropUpdate = true;
      nvidiaDropUpdate = true;
    };
    lto-znver4 = {
      kernelDropUpdate = true;
    };
    server = { };
    hardened = { };
    rc = { };
    lts = { };
  };

  # NVIDIA variant -> nvidia-cachyos module variant mapping
  nvidiaVariants = {
    gcc = { variant = "stable"; dropUpdate = true; };
    lto = { variant = "lto"; dropUpdate = true; };
    rc = { variant = "rc"; };
    server = { variant = "server"; };
    hardened = { variant = "hardened"; };
    lts = { variant = "lts"; };
  };

  variantNames = builtins.attrNames overlayAttrs;

  linuxKernelAttrs = builtins.listToAttrs (
    lib.concatMap
      (
        name:
        let
          attrs = overlayAttrs.${name};
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
      )
      variantNames
  );

  nvidiaKernelAttrs = builtins.listToAttrs (
    lib.concatMap
      (
        name:
        let
          nvidiaConf = nvidiaVariants.${name};
          pkg = cachyosPackages."cachyos-${name}";
          variantArg = { variant = nvidiaConf.variant; };
        in
        [
          {
            name = "nvidia_cachyos-${name}";
            value =
              let drv = callOverride ./nvidia-cachyos (variantArg // { linuxPackages = pkg; });
              in if nvidiaConf ? dropUpdate then dropUpdate drv else drv;
          }
          {
            name = "nvidia_cachyos-${name}-open";
            value = dropUpdate (callOverride ./nvidia-cachyos (variantArg // { linuxPackages = pkg; })).open;
          }
        ]
      )
      (builtins.attrNames nvidiaVariants)
  );
in
linuxKernelAttrs
// {
  nvidia_cachyos = dropUpdate (callOverride ./nvidia-cachyos { linuxPackages = cachyosPackages."cachyos-gcc"; });
  nvidia_cachyos-open = dropUpdate (callOverride ./nvidia-cachyos { linuxPackages = cachyosPackages."cachyos-gcc"; }).open;
}
// nvidiaKernelAttrs
// {
  zfs_cachyos = prev.zfs_2_4.overrideAttrs (prevAttrs: {
    src = cachyosPackages.zfs.src;
    patches = [ ];
    passthru = prevAttrs.passthru // {
      kernelModuleAttribute = "zfs_cachyos";
    };
    postPatch = builtins.replaceStrings [ "grep --quiet '^Linux-M" ] [ "# " ] prevAttrs.postPatch;
  });
}
