{
  allPackages,
  recursionHelper,
  lib,
  projectUtils,
  system,
  writeText,
}:
let
  evalResult =
    k: v:
    "${system}\t${k}\t${projectUtils.drvHash v}\t${builtins.unsafeDiscardStringContext v.outPath}";

  warn =
    k: _v: message:
    "${system}\t${k}\t_\t${message}";

  packagesEval = recursionHelper.derivations warn evalResult allPackages;

  packagesEvalSorted = lib.lists.naturalSort (lib.lists.flatten packagesEval);
in
writeText "project-eval.tsv" (lib.strings.concatStringsSep "\n" packagesEvalSorted)
