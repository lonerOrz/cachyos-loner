{
  self,
  lib,
  system,
}:

let
  pkgs = self.packages.${system};
  linuxPkgs = self.legacyPackages.${system} or { };

  # Modules allowed into the CI cache queue.
  allowedModules = [
    "zfs_cachyos"
    "zenpower"
    "v4l2loopback"
  ];

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

  knownVariants =
    let
      prefix = "linuxPackages_cachyos-";
      names = builtins.attrNames linuxPkgs;
      prefixed = builtins.filter (n: lib.hasPrefix prefix n) names;
      variants = map (n: lib.removePrefix prefix n) prefixed;
    in
    # Sort by length descending so longest match wins (lto-znver4 before lto)
    builtins.sort (a: b: (builtins.stringLength a) > (builtins.stringLength b)) (
      lib.unique (builtins.filter (v: v != "") variants)
    );

  extractVariant =
    name:
    let
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

  # Three-way classification.
  isKernel = name: lib.strings.hasInfix "linux_cachyos" name || lib.strings.hasInfix ".kernel" name;
  isNvidia = name: lib.strings.hasInfix "nvidia" name;
  # modules = everything else (zfs, v4l2loopback, acpi_call, etc.)

  isBroken =
    pkg:
    let
      r = builtins.tryEval (pkg.meta.broken or pkg.meta.unsupported or false);
    in
    r.success && r.value != false && r.value != null;

  extractModuleDrvs =
    variant: mod:
    let
      val = tryAttr linuxPkgs.${variant} mod;
      prefix = "legacyPackages.${system}.${variant}.${mod}";
    in
    if val == null || (isDerivation val && isBroken val) then
      [ ]
    else if !(builtins.elem mod allowedModules) then
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
            v != null && isDerivation v && !(isBroken v)
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
  # Tier 1: kernels — top-level only (flatPackages), no nested duplicates.
  # Filter out the bare "linux_cachyos" alias (unqualified, no variant suffix).
  kernels = lib.filterAttrs (
    name: v: isKernel name && v.drvPath != null && name != "linux_cachyos"
  ) flatPackages;

  # Tier 2: nvidia — from flatPackages.
  nvidia = lib.filterAttrs (name: v: isNvidia name && v.drvPath != null) flatPackages;

  # Tier 3: modules — from linuxPackages sets (allNested), excluding nvidia.
  modules = lib.filterAttrs (name: v: !(isNvidia name) && v.drvPath != null) allNested;
}
