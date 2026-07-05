{ lib, nixpkgs ? null, defaultOverlay ? null }:

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

  replaceStartingWith =
    prefix: newSuffix:
    builtins.map (x: if lib.strings.hasPrefix prefix x then prefix + newSuffix else x);

  applyOverlay =
    {
      overlay ? defaultOverlay,
      projectPkgs ? null,
      onlyDerivations ? false,
      pkgs,
    }:
    let
      ourPackages = if projectPkgs != null then projectPkgs else overlay overlayFinal pkgs;
      overlayFinal = (ourPackages // pkgs) // {
        callPackage = pkgs.newScope overlayFinal;
      };
    in
    if onlyDerivations then
      pkgs.lib.attrsets.filterAttrs (
        _k: v: (builtins.tryEval v).success && pkgs.lib.attrsets.isDerivation v
      ) ourPackages
    else
      ourPackages;

  getPkgs =
    system:
    import nixpkgs {
      inherit system;
      config = {
        allowBroken = true;
        allowUnfree = true;
        allowUnsupportedSystem = true;
        nvidia.acceptLicense = true;
      };
    };
}
