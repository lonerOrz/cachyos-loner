{
  cachyConfig,
  kconfigToNix,
  config,
  configfile,
  utils,
  lib,
  linuxManualConfig,
  stdenv,
  commonMakeFlags,
  # Weird injections
  kernelPatches ? [ ],
  features ? null,
  randstructSeed ? "",
  # For tests
  kernelPackages,
  flakes,
  final,
}:
let
  version = cachyConfig.versions.linux.version;
in
(linuxManualConfig {
  inherit
    stdenv
    version
    features
    randstructSeed
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
    passthru =
      prevAttrs.passthru
      // {
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
        tests = (prevAttrs.passthru.tests or { }) // {
          plymouth = import ./test.nix {
            inherit kernelPackages;
            inherit (flakes) nixpkgs;
            rootFlake = flakes.self;
          } final;
        };
      };
  })
