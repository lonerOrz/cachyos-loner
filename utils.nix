{ lib }:

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
}
