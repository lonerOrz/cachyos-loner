{
  cachyConfig,
  kconfigToNix,
  config,
  configfile,
  lib,
  linuxManualConfig,
  stdenv,
  commonMakeFlags,
  kernelPatches ? [ ],
}:

let
  version = cachyConfig.versions.linux.version;
in
(linuxManualConfig {
  inherit
    stdenv
    version
    ;
  inherit (configfile) src;

  # Ensure module directory matches EXTRAVERSION appended by CachyOS.
  modDirVersion = lib.versions.pad 3 "${version}${cachyConfig.versions.suffix}";

  inherit config configfile;
  # Disallow IFD since config is passed as a pre-transformed Nix attribute set.
  allowImportFromDerivation = false;

  # Format raw patch paths into standard Nixpkgs kernel patch structures.
  kernelPatches =
    kernelPatches
    ++ builtins.map (filename: {
      name = builtins.baseNameOf filename;
      patch = filename;
    }) configfile.passthru.kernelPatches;

  extraMeta = {
    maintainers = with lib.maintainers; [
      dr460nf1r3
      pedrohlc
    ];
    inherit (configfile.meta) platforms;
  };
}).overrideAttrs
  (prevAttrs: {
    # Append EXTRAVERSION suffix (-cachyos) directly to top-level Makefile.
    postPatch = prevAttrs.postPatch + configfile.extraVerPatch;

    # Expose metadata and features on kernel passthru.
    passthru = prevAttrs.passthru // {
      inherit cachyConfig kconfigToNix commonMakeFlags;
      features = {
        efiBootStub = true;
        ia32Emulation = true;
        netfilterRPFilter = true;
      };
      isLTS = lib.hasSuffix "-lts" (cachyConfig.taste or "");
      isZen = true;
      isHardened = cachyConfig.cpuSched == "hardened";
      isLibre = false;
    };
  })
