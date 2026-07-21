{
  self,
  lib,
  system,
}:

let
  pkgs = self.packages.${system};
  linuxPkgs = self.legacyPackages.${system} or { };

  tryDrvPath =
    pkg:
    let
      r = builtins.tryEval (pkg.drvPath or null);
    in
    if r.success && r.value != null then r.value else null;

  tryAttr =
    set: attr:
    let
      r = builtins.tryEval (set.${attr} or null);
    in
    if r.success then r.value else null;

  isDerivation = x: builtins.isAttrs x && (x.type or null) == "derivation";

  # Extract variant name from a package key by matching "-<variant>" segments.
  # Tries longest variants first (lto-znver4 before lto) to avoid false matches.
  # Falls back to "gcc" for unsuffixed names (nvidia_cachyos, zfs_cachyos, linux_cachyos alias).
  extractVariant =
    name:
    let
      knownVariants = [
        "lto-znver4"
        "lto"
        "hardened"
        "server"
        "lts"
        "rc"
        "gcc"
      ];
      tryVariant =
        v:
        let
          parts = lib.splitString "-${v}" name;
          lastPart = lib.last parts;
        in
        if lastPart == "" || lib.hasPrefix "." lastPart || lib.hasPrefix "-" lastPart then v else null;
      found = lib.findFirst (v: v != null) null (map tryVariant knownVariants);
    in
    if found != null then found else "gcc";

  # Kernel entries: anything with "linux_cachyos" or ".kernel" in the key name.
  isKernelEntry =
    name: lib.strings.hasInfix "linux_cachyos" name || lib.strings.hasInfix ".kernel" name;

  # Module entries: nvidia* (except when inside linuxPackages sets) and zfs_cachyos.
  isModuleEntry =
    name:
    let
      has = s: lib.strings.hasInfix s name;
    in
    (has "nvidia" || has "zfs_cachyos") && !(has "nvidia" && has "linuxPackages");

  extractModuleDrvs =
    variant: mod:
    let
      val = tryAttr linuxPkgs.${variant} mod;
      prefix = "legacyPackages.${system}.${variant}.${mod}";
    in
    if val == null then
      [ ]
    else if isDerivation val then
      [
        {
          name = prefix;
          value = {
            drvPath = tryDrvPath val;
            variant = extractVariant prefix;
          };
        }
      ]
    else if builtins.isAttrs val && !(val ? type) then
      map
        (n: {
          name = "${prefix}.${n}";
          value = {
            drvPath = tryDrvPath (tryAttr val n);
            variant = extractVariant "${prefix}.${n}";
          };
        })
        (
          builtins.filter (
            n:
            let
              v = tryAttr val n;
            in
            v != null && isDerivation v
          ) (builtins.attrNames val)
        )
    else
      [ ];

  flatPackages = lib.genAttrs (builtins.attrNames pkgs) (name: {
    drvPath = tryDrvPath pkgs.${name};
    variant = extractVariant name;
  });

  allNested = builtins.listToAttrs (
    lib.concatMap (
      variant:
      let
        s = linuxPkgs.${variant} or { };
      in
      if builtins.isAttrs s then
        lib.concatMap (mod: extractModuleDrvs variant mod) (builtins.attrNames s)
      else
        [ ]
    ) (builtins.attrNames linuxPkgs)
  );

  all = lib.filterAttrs (_: v: v.drvPath != null) (flatPackages // allNested);

in
{
  kernels = lib.filterAttrs (name: _: isKernelEntry name) all;
  modules = lib.filterAttrs (name: _: isModuleEntry name) all;
}
