{
  final,
  ...
}@inputs:

let
  inherit (final.stdenv) isx86_64 isLinux;
  inherit (final.lib.trivial) importJSON;
  lib = final.lib;

  utils = import ../utils.nix { lib = final.lib; };

  mainVersions = importJSON ./versions.json;
  hardenedVersions = importJSON ./versions-hardened.json;
  ltsVersions = importJSON ./versions-lts.json;
  rcVersions = importJSON ./versions-rc.json;
  serverVersions = importJSON ./versions-server.json;
  hardenedVars = importJSON ./config-vars/cachyos-hardened.json;
  ltoVars = importJSON ./config-vars/cachyos-lto.json;
  ltsVars = importJSON ./config-vars/cachyos-lts.json;
  rcVars = importJSON ./config-vars/cachyos-rc.json;
  serverVars = importJSON ./config-vars/cachyos-server.json;

  pkgsLLVM = import ./lib/llvm-pkgs.nix inputs;

  preventBuildingKernelModules = _kernel: _final: prev: prev // { recurseForDerivations = false; };

  brokenReplacement = final.hello.overrideAttrs (prevAttrs: {
    meta = prevAttrs.meta // {
      platform = [ ];
      broken = true;
    };
  });

  isUnsupported = !isx86_64 || !isLinux;

  mkCachyKernel =
    if isUnsupported then
      _attrs: {
        kernel = brokenReplacement;
        recurseForDerivations = false;
      }
    else
      {
        callPackage ? final.callPackage,
        ...
      }@attrs:
      callPackage ./packages-for.nix (
        {
          versions = mainVersions;
          inherit inputs utils;
          cachyOverride = newAttrs: mkCachyKernel (attrs // newAttrs);
        }
        // attrs
      );

  flavors = import ./flavors.nix {
    inherit final lib pkgsLLVM ltoVars ltsVars rcVars serverVars hardenedVars
      mainVersions ltsVersions rcVersions serverVersions hardenedVersions
      preventBuildingKernelModules;
  };
in
{
  cachyos-sched-ext = throw "\"sched-ext\" patches were merged with \"cachyos\" flavor.";
}
// builtins.listToAttrs (
  lib.mapAttrsToList (name: attrs: {
    name = "cachyos-${name}";
    value = mkCachyKernel attrs;
  }) flavors
)
