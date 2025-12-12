{
  allPackages,
  recursionHelper,
  flakeSelf,
  lib,
  projectUtils,
  writeText,
  stdenv,
}:

let
  allPackagesList = builtins.map (xsx: xsx.drv) (
    lib.lists.filter (xsx: xsx.drv != null) packagesEval
  );

  inherit (stdenv.hostPlatform) system;

  # failures = import "${flakeSelf}/maintenance/failures.${system}.nix"; # Removed: maintenance directory no longer exists

  allOuts =
    key: drv:
    let
      pair = output: {
        name = recursionHelper.join key output;
        value = builtins.unsafeDiscardStringContext drv.${output}.outPath;
      };
    in
    builtins.listToAttrs (map pair drv.outputs);

  derivationMap =
    key: drv:
    let
      deps = projectUtils.internalDeps allPackagesList drv;
      depsCond = builtins.map (dep: projectUtils.drvHash dep) deps;
      mainOutPath = builtins.unsafeDiscardStringContext drv.outPath;
      thisVar = projectUtils.drvHash drv;
      failed = null; # Changed: failures file no longer exists
    in
    if mainOutPath == failed then
      doNotBuild key {
        broken = mainOutPath;
        this = thisVar;
        inherit system;
      }
    else
      {
        cmd = {
          build = true;
          artifacts = allOuts key drv;
          deps = depsCond;
          this = thisVar;
          thisOut = projectUtils.outHash drv;
          issue = failed;
          inherit key mainOutPath system;
        };
        inherit deps drv;
      };

  commentWarn =
    key: _v: message:
    doNotBuild key { warn = message; };

  doNotBuild = key: data: {
    cmd = {
      build = false;
      inherit key;
    }
    // data;
    drv = null;
    deps = [ ];
  };

  packagesEval = lib.lists.flatten (
    recursionHelper.derivations commentWarn derivationMap allPackages
  );

  depFirstSorter =
    pkgA: pkgB:
    if pkgA.drv == null || pkgB.drv == null then false else projectUtils.drvElem pkgA.drv pkgB.deps;

  packagesEvalSorted = lib.lists.toposort depFirstSorter packagesEval;

  packagesCmds = builtins.map (pkg: pkg.cmd) packagesEvalSorted.result;

  finalJSON = writeText "project-dry-build.json" (lib.generators.toJSON { } packagesCmds);
in
finalJSON.overrideAttrs (oldAttrs: {
  passthru = (oldAttrs.passthru or { }) // {
    inherit
      packagesCmds
      system
      flakeSelf
      packagesEval
      ;
  };
})
