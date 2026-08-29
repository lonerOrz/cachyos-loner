{ flakeRef }:

let
  flake = builtins.getFlake flakeRef;
  pkgs = flake.packages.x86_64-linux;

  # Inspect package passthru to determine updateScript capabilities.
  packageInfo =
    name:
    let
      passthru = pkgs.${name}.passthru or { };
      updateScript = pkgs.${name}.updateScript or passthru.updateScript or null;
      isDrv = if updateScript == null then false else (updateScript.type or "") == "derivation";
    in
    {
      autoUpdate = (passthru.autoUpdate or true) != false;
      isDerivation = isDrv;
      inherit updateScript;
      updateArgs = passthru.updateArgs or [ ];
    };
in
builtins.mapAttrs (name: _: packageInfo name) pkgs
