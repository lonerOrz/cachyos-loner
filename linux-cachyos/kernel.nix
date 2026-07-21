{
  cachyConfig,
  kconfigToNix,
  config,
  configfile,
  lib,
  linuxManualConfig,
  stdenv,
  commonMakeFlags,
  # Weird injections
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
  modDirVersion = lib.versions.pad 3 "${version}${cachyConfig.versions.suffix}";

  inherit config configfile;
  allowImportFromDerivation = false;

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
    postPatch = prevAttrs.postPatch + configfile.extraVerPatch;
    # bypasses https://github.com/NixOS/nixpkgs/issues/216529
    passthru = prevAttrs.passthru // {
      inherit cachyConfig kconfigToNix commonMakeFlags;
      features = {
        efiBootStub = true;
        ia32Emulation = true;
        netfilterRPFilter = true;
      };
      isLTS = false;
      isZen = true;
      isHardened = cachyConfig.cpuSched == "hardened";
      isLibre = false;
    };
  })
