{
  lib,
  nixpkgs ? null,
}:

{
  # Mark a derivation as broken in its metadata.
  markBroken =
    drv:
    drv.overrideAttrs (prevAttrs: {
      meta = (prevAttrs.meta or { }) // {
        broken = true;
      };
    });

  # Chain .override and .overrideAttrs in a single call.
  multiOverride = prev: newInputs: (prev.override newInputs).overrideAttrs;

  # Scope-based override that automatically injects matching args from newScope.
  overrideFull =
    newScope: prev:
    let
      args = prev.override.__functionArgs or { };
      names = builtins.filter (arg: builtins.hasAttr arg newScope) (builtins.attrNames args);
      values = lib.attrsets.genAttrs names (arg: builtins.getAttr arg newScope);
    in
    prev.override values;

  # Replace makeFlags list elements matching a given prefix.
  replaceStartingWith =
    prefix: newSuffix:
    builtins.map (x: if lib.strings.hasPrefix prefix x then prefix + newSuffix else x);

  # Instantiate nixpkgs with unfree and nvidia license allowances.
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
