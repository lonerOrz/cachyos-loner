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

  enforcedConfigFeatures = config // {
    "CONFIG_MODULES" = "y";
  };
in
(linuxManualConfig {
  inherit
    stdenv
    version
    ;
  inherit (configfile) src;

  # Ensure module directory matches EXTRAVERSION appended by CachyOS.
  modDirVersion = lib.versions.pad 3 "${version}${cachyConfig.versions.suffix}";

  inherit configfile;
  config = enforcedConfigFeatures;
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
    # Keep nixpkgs' own makeFlags (reproducible timestamp, DTC_FLAGS, undefine
    # src) and append ours so the toolchain/RUSTC flags win.
    makeFlags = prevAttrs.makeFlags ++ commonMakeFlags;
    # AutoFDO/Propeller profiles are referenced by path in makeFlags; register
    # them as inputs so Nix keeps them in the sandbox.
    nativeBuildInputs =
      prevAttrs.nativeBuildInputs
      ++ lib.optionals (cachyConfig.autoFDOProfile != null) [ cachyConfig.autoFDOProfile ]
      ++ lib.optionals (cachyConfig.propellerProfiles != null) [ cachyConfig.propellerProfiles ];
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
