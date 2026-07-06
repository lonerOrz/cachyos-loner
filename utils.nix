{ lib, nixpkgs ? null }:

{
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
