{ lib, nixpkgs, defaultOverlay }:

rec {
  markBroken =
    drv:
    drv.overrideAttrs (prevAttrs: {
      meta = (prevAttrs.meta or { }) // {
        broken = true;
      };
    });

  multiOverride = prev: newInputs: (prev.override newInputs).overrideAttrs;

  overrideFull =
    newScope: prev:
    let
      args = prev.override.__functionArgs;
      names = builtins.filter (arg: builtins.hasAttr arg newScope) (builtins.attrNames args);
      values = lib.attrsets.genAttrs names (arg: builtins.getAttr arg newScope);
    in
    prev.override values;

  setAttrsPlatforms =
    platforms:
    builtins.mapAttrs (
      _k: v:
      if (v ? "overrideAttrs") then
        v.overrideAttrs (prevAttrs: {
          meta = (prevAttrs.meta or { }) // {
            platforms = lib.lists.intersectLists (prevAttrs.meta.platforms or [ ]) platforms;
            platformsOrig = prevAttrs.meta.platforms or [ ];
            badPlatforms = [ ];
          };
        })
      else
        v
    );

  shorter = builtins.substring 0 7;

  recurseForDerivations = false;

  applyOverlay =
    {
      replace ? false,
      merge ? false,
      overlay ? defaultOverlay,
      projectPkgs ? null,
      onlyDerivations ? false,
      pkgs,
    }:
    let
      fullPackages = if replace then pkgs // ourPackages else ourPackages // pkgs;
      overlayFinal = fullPackages // {
        callPackage = pkgs.newScope overlayFinal;
      };
      ourPackages = if projectPkgs != null then projectPkgs else overlay overlayFinal pkgs;
      preFilter = if merge then overlayFinal else ourPackages;
    in
    if onlyDerivations then
      pkgs.lib.attrsets.filterAttrs (
        _k: v: (builtins.tryEval v).success && pkgs.lib.attrsets.isDerivation v
      ) preFilter
    else
      preFilter;

  getPkgs =
    system:
    import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        allowUnsupportedSystem = true;
        nvidia.acceptLicense = true;
      };
    };
}
