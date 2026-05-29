{
  description = "Nix flake for linux_cachyos.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      # Common list of supported systems
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Helper to generate attributes for all supported systems
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Define the main overlay
      defaultOverlay = final: prev:
      let
        # Required to load version files.
        inherit (final.lib.trivial) importJSON;

        # Our utilities/helpers.
        projectUtils =
          let
            lib = final.lib;
            projectOverlay = defaultOverlay;
          in
          rec {
            # For viewing in our documentation page.
            _description = "Pack of functions that are useful for Chaotic-Project and might become useful for you too";

            # All the ways I found to overlay in nixpkgs
            applyOverlay =
              {
                replace ? false,
                merge ? false,
                overlay ? projectOverlay,
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

            # When `removeByBaseName` and `removeByURL` can't help, use this to drop patches.
            dropN = qty: list: lib.lists.take (builtins.length list - qty) list;

            # Helps when batch-overriding.
            dropAttrsUpdateScript = builtins.mapAttrs (
              _k: v: if (v.passthru.updateScript or null) != null then v.overrideAttrs dropUpdateScript else v
            );

            # Helps when overriding.
            dropUpdateScript = prevAttrs: { passthru = removeAttrs prevAttrs.passthru [ "updateScript" ]; };

            # Helps when overriding.
            drvDropUpdateScript = package: package.overrideAttrs dropUpdateScript;

            # NOTE: Don't use in your system's configuration, this helps in the repo's infra.
            # Checks if a derivation is in a list.
            drvElem = x: xs: builtins.elem x.drvPath (builtins.map (xsx: xsx.drvPath) xs);

            # NOTE: Don't use in your system's configuration, this helps in the repo's infra
            # Get's the hash of a derivation.
            drvHash =
              drv:
              builtins.substring 0 32 (builtins.baseNameOf (builtins.unsafeDiscardStringContext drv.drvPath));

            # NOTE: Don't use in your system's configuration, this helps in the repo's infra
            # Get's the hash of a derivation.
            outHash =
              drv:
              builtins.substring 0 32 (builtins.baseNameOf (builtins.unsafeDiscardStringContext drv.outPath));

            # NOTE: Don't use in your system's configuration, this helps in the repo's infra.
            # Finds dependencies in a derivation that are also present in a attrset filled with derivations.
            internalDeps =
              packages: drv:
              let
                allDeps = lib.strings.concatStringsSep " " (
                  builtins.attrNames (builtins.getContext (builtins.toJSON drv.drvAttrs))
                );
              in
              builtins.filter (
                x: lib.strings.hasInfix (builtins.unsafeDiscardStringContext x.drvPath) allDeps
              ) packages;

            # Helps when converting flakes to src.
            gitToVersion = src: "unstable-${src.lastModifiedDate}-${src.shortRev}";

            # Helps when converting flakes to src.
            gitOverride =
              src: drv:
              drv.overrideAttrs (_prevAttrs: {
                version = gitToVersion src;
                inherit src;
              });

            # Don't waste user's time.
            markBroken =
              drv:
              drv.overrideAttrs (prevAttrs: {
                meta = (prevAttrs.meta or { }) // {
                  broken = true;
                };
              });

            # Helps when overriding both inputs and outputs attrs.
            multiOverride = prev: newInputs: (prev.override newInputs).overrideAttrs;

            # Helps when overriding both inputs and outputs attrs, multiple times.
            multiOverrides =
              prev: newInputs: lib.lists.foldl (accu: accu.overrideAttrs) (prev.override newInputs);

            # Single-value optional attr
            optionalAttr =
              key: pred: value:
              if pred then { "${key}" = value; } else { };

            # Helps when overriding.
            overrideDescription = descriptionMap: prevAttrs: {
              meta = (rejectAttr "longDescription" prevAttrs.meta) // {
                description = descriptionMap prevAttrs.meta.description;
              };
            };

            # Helps replacing all the dependencies in a derivation.
            overrideFull =
              newScope: prev:
              let
                args = prev.override.__functionArgs;
                names = builtins.filter (arg: builtins.hasAttr arg newScope) (builtins.attrNames args);
                values = lib.attrsets.genAttrs names (arg: builtins.getAttr arg newScope);
              in
              prev.override values;

            # Helps removing attrs.
            rejectAttr = x: lib.attrsets.filterAttrs (k: _v: k != x);

            # Helps when dropping patches.
            removeByBaseName = baseName: builtins.filter (x: builtins.baseNameOf x != baseName);

            # Helps when dropping patches.
            removeByName = baseName: builtins.filter (x: (x.name or null) != baseName);

            # Helps when dropping multiple patches at once, same as the one before but taking a lit of names.
            removeByNames = baseNames: builtins.filter (x: !builtins.elem (x.name or null) baseNames);

            # Helps when dropping patches.
            removeByBaseNames =
              baseNames: builtins.filter (x: !builtins.elem (builtins.baseNameOf x) baseNames);

            # Helps when dropping patches.
            removeByURL = url: builtins.filter (x: !(lib.attrsets.isDerivation x) || (x.url or null) != url);

            # Helps when dropping flags.
            removeByPrefix =
              prefix:
              let
                prefixLen = builtins.stringLength prefix;
              in
              builtins.filter (s: builtins.substring 0 prefixLen s != prefix);

            # Helps when dropping flags.
            removeByPrefixes =
              prefixes: xs: lib.lists.foldl (accu: prefix: removeByPrefix prefix accu) xs prefixes;

            # Helps updating flags
            replaceStartingWith =
              prefix: newSuffix:
              builtins.map (x: if lib.strings.hasPrefix prefix x then prefix + newSuffix else x);

            # Helps when batch-overriding.
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

            # For revs
            shorter = builtins.substring 0 7;

            # Like `lib.fakeHash`, but beautier.
            unreachableHash = "sha256-2342234223422342234223422342234223422342069=";

            # We don't want builders playing around here.
            recurseForDerivations = false;
          };
        inherit (projectUtils) multiOverride overrideDescription drvDropUpdateScript;

        # Helps when calling .nix that will override packages.
        callOverride =
          path: attrs:
          import path (
            {
              inherit
                final
                projectUtils
                prev
                ;
              flakes = inputs;
            }
            // attrs
          );
        # Too much variations
        cachyosPackages = callOverride ./pkgs/linux-cachyos { };

        # Required for kernel packages
        inherit (final.stdenv) isLinux isx86_64;

      in
      {
        inherit projectUtils;

        linux_cachyos = drvDropUpdateScript cachyosPackages.cachyos-gcc.kernel;
        linux_cachyos-lto = drvDropUpdateScript cachyosPackages.cachyos-lto.kernel;

        linux_cachyos-gcc = drvDropUpdateScript cachyosPackages.cachyos-gcc.kernel;
        linux_cachyos-server = drvDropUpdateScript cachyosPackages.cachyos-server.kernel;
        linux_cachyos-hardened = drvDropUpdateScript cachyosPackages.cachyos-hardened.kernel;
        linux_cachyos-rc = cachyosPackages.cachyos-rc.kernel;
        linux_cachyos-lts = cachyosPackages.cachyos-lts.kernel;

        linuxPackages_cachyos = cachyosPackages.cachyos-gcc;
        linuxPackages_cachyos-lto = cachyosPackages.cachyos-lto;

        linuxPackages_cachyos-gcc = cachyosPackages.cachyos-gcc;
        linuxPackages_cachyos-server = cachyosPackages.cachyos-server;
        linuxPackages_cachyos-hardened = cachyosPackages.cachyos-hardened;
        linuxPackages_cachyos-rc = cachyosPackages.cachyos-rc;
        linuxPackages_cachyos-lts = cachyosPackages.cachyos-lts;

        zfs_cachyos = cachyosPackages.zfs;
      };

      # Define utility functions
      utils =
        let
          lib = nixpkgs.lib;
          projectOverlay = defaultOverlay;
        in
        rec {
          # For viewing in our documentation page.
          _description = "Pack of functions that are useful for Chaotic-Project and might become useful for you too";

          # All the ways I found to overlay in nixpkgs
          applyOverlay =
            {
              replace ? false,
              merge ? false,
              overlay ? projectOverlay,
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

          # When `removeByBaseName` and `removeByURL` can't help, use this to drop patches.
          dropN = qty: list: lib.lists.take (builtins.length list - qty) list;

          # Helps when batch-overriding.
          dropAttrsUpdateScript = builtins.mapAttrs (
            _k: v: if (v.passthru.updateScript or null) != null then v.overrideAttrs dropUpdateScript else v
          );

          # Helps when overriding.
          dropUpdateScript = prevAttrs: { passthru = removeAttrs prevAttrs.passthru [ "updateScript" ]; };

          # Helps when overriding.
          drvDropUpdateScript = package: package.overrideAttrs dropUpdateScript;

          # NOTE: Don't use in your system's configuration, this helps in the repo's infra.
          # Checks if a derivation is in a list.
          drvElem = x: xs: builtins.elem x.drvPath (builtins.map (xsx: xsx.drvPath) xs);

          # NOTE: Don't use in your system's configuration, this helps in the repo's infra
          # Get's the hash of a derivation.
          drvHash =
            drv:
            builtins.substring 0 32 (builtins.baseNameOf (builtins.unsafeDiscardStringContext drv.drvPath));

          # NOTE: Don't use in your system's configuration, this helps in the repo's infra
          # Get's the hash of a derivation.
          outHash =
            drv:
            builtins.substring 0 32 (builtins.baseNameOf (builtins.unsafeDiscardStringContext drv.outPath));

          # NOTE: Don't use in your system's configuration, this helps in the repo's infra.
          # Finds dependencies in a derivation that are also present in a attrset filled with derivations.
          internalDeps =
            packages: drv:
            let
              allDeps = lib.strings.concatStringsSep " " (
                builtins.attrNames (builtins.getContext (builtins.toJSON drv.drvAttrs))
              );
            in
            builtins.filter (
              x: lib.strings.hasInfix (builtins.unsafeDiscardStringContext x.drvPath) allDeps
            ) packages;

          # Helps when converting flakes to src.
          gitToVersion = src: "unstable-${src.lastModifiedDate}-${src.shortRev}";

          # Helps when converting flakes to src.
          gitOverride =
            src: drv:
            drv.overrideAttrs (_prevAttrs: {
              version = gitToVersion src;
              inherit src;
            });

          # Don't waste user's time.
          markBroken =
            drv:
            drv.overrideAttrs (prevAttrs: {
              meta = (prevAttrs.meta or { }) // {
                broken = true;
              };
            });

          # Helps when overriding both inputs and outputs attrs.
          multiOverride = prev: newInputs: (prev.override newInputs).overrideAttrs;

          # Helps when overriding both inputs and outputs attrs, multiple times.
          multiOverrides =
            prev: newInputs: lib.lists.foldl (accu: accu.overrideAttrs) (prev.override newInputs);

          # Single-value optional attr
          optionalAttr =
            key: pred: value:
            if pred then { "${key}" = value; } else { };

          # Helps when overriding.
          overrideDescription = descriptionMap: prevAttrs: {
            meta = (rejectAttr "longDescription" prevAttrs.meta) // {
              description = descriptionMap prevAttrs.meta.description;
            };
          };

          # Helps replacing all the dependencies in a derivation.
          overrideFull =
            newScope: prev:
            let
              args = prev.override.__functionArgs;
              names = builtins.filter (arg: builtins.hasAttr arg newScope) (builtins.attrNames args);
              values = lib.attrsets.genAttrs names (arg: builtins.getAttr arg newScope);
            in
            prev.override values;

          # Helps removing attrs.
          rejectAttr = x: lib.attrsets.filterAttrs (k: _v: k != x);

          # Helps when dropping patches.
          removeByBaseName = baseName: builtins.filter (x: builtins.baseNameOf x != baseName);

          # Helps when dropping patches.
          removeByName = baseName: builtins.filter (x: (x.name or null) != baseName);

          # Helps when dropping multiple patches at once, same as the one before but taking a lit of names.
          removeByNames = baseNames: builtins.filter (x: !builtins.elem (x.name or null) baseNames);

          # Helps when dropping patches.
          removeByBaseNames =
            baseNames: builtins.filter (x: !builtins.elem (builtins.baseNameOf x) baseNames);

          # Helps when dropping patches.
          removeByURL = url: builtins.filter (x: !(lib.attrsets.isDerivation x) || (x.url or null) != url);

          # Helps when dropping flags.
          removeByPrefix =
            prefix:
            let
              prefixLen = builtins.stringLength prefix;
            in
            builtins.filter (s: builtins.substring 0 prefixLen s != prefix);

          # Helps when dropping flags.
          removeByPrefixes =
            prefixes: xs: lib.lists.foldl (accu: prefix: removeByPrefix prefix accu) xs prefixes;

          # Helps updating flags
          replaceStartingWith =
            prefix: newSuffix:
            builtins.map (x: if lib.strings.hasPrefix prefix x then prefix + newSuffix else x);

          # Helps when batch-overriding.
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

          # For revs
          shorter = builtins.substring 0 7;

          # Like `lib.fakeHash`, but beautier.
          unreachableHash = "sha256-2342234223422342234223422342234223422342069=";

          # We don't want builders playing around here.
          recurseForDerivations = false;
        };

      # Function to get pkgs for a specific system
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

    in
    {
      # Expose the default overlay
      overlays.default = defaultOverlay;

      # Generate packages for all systems
      packages = forAllSystems (
        system:
        utils.applyOverlay {
          pkgs = getPkgs system;
          onlyDerivations = true;
        }
      );

      # Generate legacy packages for all systems
      legacyPackages = forAllSystems (
        system:
        utils.applyOverlay {
          pkgs = getPkgs system;
        }
      );

      # Generate dev shells for all systems
      devShells = forAllSystems (system:
        let
          projectPkgs = self.legacyPackages.${system};
          nixPkgs = nixpkgs.legacyPackages.${system};

          pkgs = utils.applyOverlay {
            inherit projectPkgs;
            pkgs = nixPkgs;
            replace = true;
            merge = true;
          };

          mkShell =
            if nixPkgs.stdenv.isLinux then
              opts:
              pkgs.mkShell (
                opts
                // {
                  env = (opts.env or { }) // {
                    # as seen on https://nixos.wiki/wiki/Locales
                    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
                  };
                }
              )
            else
              pkgs.mkShell;

          recursionHelper =
            let
              lib = pkgs.lib;
              system = pkgs.stdenv.hostPlatform.system;
              parsedSystem = lib.systems.parse.mkSystemFromString system;
            in
            rec {
              join = namespace: current: if namespace != "" then "${namespace}.${current}" else current;

              # limit: integer | "explicit"
              # warnFn: k -> v -> message -> result
              # mapFn: k -> v -> result
              # root: attrset | derivation
              derivationsLimited =
                limit: warnFn: mapFn: root:
                let
                  recursive =
                    level: namespace: key: v:
                    let
                      fullKey = join namespace key;
                    in
                    if (builtins.tryEval v).success then
                      (
                        if lib.attrsets.isDerivation v then
                          (
                            if (v.meta.broken or true) then
                              warnFn fullKey v "marked broken"
                            else if !(builtins.tryEval v.outPath).success then
                              warnFn fullKey v "out eval broken"
                            else if
                              (
                                (v.meta.platforms or [ ]) != [ ]
                                && !(
                                  builtins.elem system v.meta.platforms
                                  || lib.systems.inspect.matchAnyAttrs (builtins.filter builtins.isAttrs v.meta.platforms) parsedSystem
                                )
                              )
                            then
                              warnFn fullKey v "not marked compatible"
                            else if
                              (
                                (v.meta.badPlatforms or [ ]) != [ ]
                                && (
                                  builtins.elem system v.meta.badPlatforms
                                  || lib.systems.inspect.matchAnyAttrs (builtins.filter builtins.isAttrs v.meta.badPlatforms) parsedSystem
                                )
                              )
                            then
                              warnFn fullKey v "marked incompatible"
                            else if
                              (
                                v.meta.unfree or true
                                && !(v.meta.project.bypassLicense or false)
                                && v.meta.license != lib.licenses.unfreeRedistributable
                              )
                            then
                              warnFn fullKey v "unfree"
                            else
                              mapFn fullKey v
                          )
                        else if
                          (limit == null || limit == "explicit" || level < limit)
                          && builtins.isAttrs v
                          && (v.recurseForDerivations or (limit != "explicit" || level == 0))
                        then
                          lib.attrsets.mapAttrsToList (recursive (level + 1) fullKey) v
                        else
                          warnFn fullKey v "not a derivation"
                      )
                    else
                      warnFn fullKey v "eval broken";
                in
                recursive 0 "" "" root;

              derivations = derivationsLimited null;

              # warnFn: k -> v -> message -> result
              # mapFn: k -> v -> result
              # root: module.options
              options =
                warnFn: mapFn: root:
                let
                  recursive =
                    namespace: key: v:
                    let
                      fullKey = join namespace key;
                    in
                    if lib.options.isOption v then
                      mapFn fullKey v
                    else if builtins.isAttrs v && (v.recurseForDerivations or true) then
                      lib.attrsets.mapAttrsToList (recursive fullKey) v
                    else
                      warnFn fullKey v "not an option";
                in
                recursive "" "" root;
            };

          # Matches build.yml and full-bump.yml
          pinnedNix = pkgs.nixVersions.latest;

          dry-build =
            let
              allPackages = projectPkgs;
              flakeSelf = self;
              inherit (pkgs) lib projectUtils writeText stdenv;

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
            });

          evaluated =
            let
              allPackages = projectPkgs;
              inherit (pkgs) lib projectUtils writeText;
              system = pkgs.stdenv.hostPlatform.system;

              evalResult =
                k: v:
                "${system}\t${k}\t${projectUtils.drvHash v}\t${builtins.unsafeDiscardStringContext v.outPath}";

              warn =
                k: _v: message:
                "${system}\t${k}\t_\t${message}";

              packagesEval = recursionHelper.derivations warn evalResult allPackages;

              packagesEvalSorted = lib.lists.naturalSort (lib.lists.flatten packagesEval);
            in
            writeText "project-eval.tsv" (lib.strings.concatStringsSep "\n" packagesEvalSorted);

          bumper =
            let
              inherit (pkgs) lib coreutils gh git nix openssh writeShellScriptBin;
              allPackages = projectPkgs;
              flakeSelf = self;

              inherit (lib.strings) concatStringsSep escapeShellArg;
              inherit (lib.lists) flatten;

              path = lib.makeBinPath [
                coreutils
                git
                nix
                gh
                openssh
              ];

              evalResult =
                k: v:
                if ((v.updateScript or null) != null) then
                  "bump-package ${escapeShellArg k} "
                  + (
                    if (builtins.isList v.updateScript) then
                      concatStringsSep " " (map escapeShellArg v.updateScript)
                    else
                      escapeShellArg v.updateScript
                  )
                else
                  null;

              skip =
                _k: _v: _message:
                null;

              packagesEval = recursionHelper.derivationsLimited 2 skip evalResult allPackages;

              packagesEvalSorted = builtins.filter (x: x != null) (flatten packagesEval);
            in
            writeShellScriptBin "project-bumper" ''
              #!/usr/bin/env bash
              set -euo pipefail

              # Cleanup PATHs for reproducibility.
              PATH="${path}"
              NIX_PATH="project=${flakeSelf}:nixpkgs=${nixpkgs}"

              # All the required functions (inlined from lib.sh)
              function checkout() {
                git checkout -b "$PROJECT_BRANCH"
                git fetch origin
                git reset --hard origin/main
                return 0
              }

              function bump-flake() {
                nix flake update
                if git diff --quiet --exit-code; then
                  return 0;
                elif [ $? -eq 1 ]; then
                  echo 1;
                  git add flake.lock
                  git commit -m "flake: bump ''${PROJECT_NAME}"
                  return 0
                fi
              }

              function bump-package() {
                echo "# Bumping $1"

                _PREV=$(git rev-parse HEAD)

                for script in "''${@:2}"; do
                  $script || return 0
                done

                if [ "''${PROJECT_BUMP_REVERT:-1}" != '0' ]; then
                  _CURR=$(git rev-parse HEAD)
                  if [ "$_PREV" != "$_CURR" ]; then
                    echo "# Building $1"
                    if PROJECT_CHANGED_ONLY="git+file:$PWD?rev=$_PREV" \
                        PHASES='prepare build-jobs no-fail' \
                        nix develop --impure -c 'project-build'; \
                    then return 0
                    elif [ $? -eq 43 ]; then
                      echo "## Failed, reverting ''${_PREV}..''${_CURR}"
                      git revert --no-commit "''${_PREV}..''${_CURR}"
                      git commit -m "Revert bumping \"$1\" (failed to build)"
                    else
                      echo "## Exited with $?"
                    fi
                  fi
                fi

                return 0
              }

              function push() {
                git push origin "$PROJECT_BRANCH" -u
              }

              function create-pr() {
                gh pr create -B main -H "$PROJECT_BRANCH" \
                  --title "Bump ''${PROJECT_NAME}" \
                  --body 'Bump our packages since we do this daily.'
              }

              function deploy-cache() {
                nix develop -c 'project-build' || [ $? -eq 42 ]
              }

              # Local stuff
              PROJECT_BUMPN=''${PROJECT_BUMPN:-1}
              PROJECT_NAME=''${PROJECT_NAME:-$(date '+%Y%m%d')-$PROJECT_BUMPN}
              PROJECT_BRANCH=''${PROJECT_BRANCH:-bump/$PROJECT_NAME}

              function bump-packages() {
                ${concatStringsSep "\n  " packagesEvalSorted}
              }

              function default-phases () {
                checkout
                bump-packages
                bump-flake
                push
                create-pr
              }

              PHASES=''${PHASES:-default-phases};
              for phase in $PHASES; do $phase; done
            '';

          # The smallest and KISSer continuos-deploy I was able to create.
          builder =
            let
              inherit (pkgs) lib coreutils-full cachix curl findutils git gnugrep gnused jq nix writeShellScriptBin;

              path = lib.makeBinPath [
                coreutils-full
                cachix
                curl
                findutils
                git
                gnugrep
                gnused
                jq
                nix
              ];

              packagesCmds = map cmdMap dry-build.passthru.packagesCmds;
              inherit (dry-build.passthru) system flakeSelf;

              quote = x: "\"${x}\"";
              depVar = dep: "_dep_${dep}";
              depVarQuoted = dep: quote "$_dep_${dep}";

              allOutPaths =
                artifacts: lib.strings.concatStringsSep " \\\n  " (map quote (builtins.attrValues artifacts));
              allOutFlakeKey =
                artifacts: lib.strings.concatStringsSep " \\\n  " (map quote (builtins.attrNames artifacts));

              cmdMap =
                cmd:
                let
                  depsCond = lib.strings.concatStrings (
                    builtins.map (dep: "[ ${depVarQuoted dep} == '1' ] && ") cmd.deps
                  );
                  thisVar = depVar cmd.this;
                  knownIssue = cmd.issue or null;
                in
                if knownIssue == "skip" then
                  ''
                    ${thisVar}=0 && echo "  \"${cmd.key}\" = \"skip\";" >> new-failures.nix
                  ''
                else if cmd.build then
                  ''
                    _ALL_OUT_KEYS=(${allOutFlakeKey cmd.artifacts})
                    _ALL_OUT_PATHS=(${allOutPaths cmd.artifacts})
                    _MAIN_OUT_PATH="${cmd.mainOutPath}"
                    _MAIN_OUT_HASH=${cmd.thisOut}
                    _WHAT="${cmd.key}"
                    _KNOWN_ISSUE="${
                      if knownIssue != null && !lib.strings.isStorePath knownIssue then cmd.issue else ""
                    }"
                    _PREV=${depVarQuoted cmd.this}
                    ${depsCond}[ -z "$_PREV" ] && ${thisVar}=0 && \
                    build && ${thisVar}=1 || failure
                  ''
                else if cmd ? broken then
                  ''
                    ${thisVar}=0 && echo "  \"${cmd.key}\" = \"${cmd.broken}\";" >> new-failures.nix
                  ''
                else if cmd ? warn then
                  ''
                    echo "${cmd.key}: ${cmd.warn}" >> eval-failures.txt
                  ''
                else
                  ''
                    echo "${cmd.key}: unexplained skip" >> eval-failures.txt
                  '';
            in
            writeShellScriptBin "project-build" ''
              # Cleanup PATH for reproducibility.
              PATH="${path}"

              # Options (1)
              PROJECT_SOURCE="''${PROJECT_SOURCE:-${flakeSelf}}"
              PROJECT_TARGET="''${PROJECT_TARGET:-${system}}"

              PROJECT_PREFIX=""
              if [ -z "$PROJECT_PREFIX" ] && [ "$PROJECT_TARGET" != 'x86_64-linux' ]; then
                PROJECT_PREFIX="''${PROJECT_TARGET%-linux}."
              fi

              # All the required functions (inlined from lib.sh)
              set -euo pipefail

              # Replace temporary paths (when using $PROJECT_TEMP)
              TMPDIR="''${PROJECT_TEMP:-''${TMPDIR}}"
              NIX_BUILD_TOP="''${PROJECT_TEMP:-''${NIX_BUILD_TOP}}"
              TMP="''${PROJECT_TEMP:-''${TMP}}"
              TEMP="''${PROJECT_TEMP:-''${TEMP}}"
              TEMPDIR="''${PROJECT_TEMP:-''${TEMPDIR}}"

              # Options
              PROJECT_ENV=('NIXPKGS_ALLOW_BROKEN=1')
              PROJECT_FLAGS="''${PROJECT_FLAGS:---accept-flake-config --no-link}"
              PROJECT_WD="''${PROJECT_WD:-$(mktemp -d)}"
              PROJECT_HOME="''${PROJECT_HOME:-$HOME/.project}"
              CACHIX_REPO="''${CACHIX_REPO:-cachyos-project}"

              # Colors
              R='\033[0;31m'
              G='\033[0;32m'
              Y='\033[1;33m'
              C='\033[1;36m'
              W='\033[0m'

              # Echo helpers
              function echo_warning() {
                echo -ne "''${Y}WARNING:''${W} "
                echo "$@"
              }

              function echo_error() {
                echo -ne "''${R}ERROR:''${W} " 1>&2
                echo "$@" 1>&2
              }

              # That's how we start
              function prepare() {
                # A place for persistent advetures
                [ ! -e "$PROJECT_HOME" ] && mkdir -p "$PROJECT_HOME"

                # Create empty logs and artifacts
                [ ! -e "$PROJECT_WD" ] && mkdir -p "$PROJECT_WD"
                cd "$PROJECT_WD"
                touch push.txt errors.txt success.txt failures.txt cached.txt upstream.txt eval-failures.txt
                echo "{" > new-failures.nix

                # Warn if we don't have automated cachix
                if [ -z "''${CACHIX_AUTH_TOKEN:-}" ] && [ -z "''${CACHIX_SIGNING_KEY:-}" ]; then
                  echo_warning "No key for cachix -- building anyway."
                fi

                # Download current list of cached packages
                if [ ! -e prev-cache.txt ]; then
                  if [ -f prev-cache.json ]; then
                    echo "Re-using cached contents"
                    jq -r '.[]' prev-cache.json > prev-cache.txt
                  elif [ -n "''${CACHIX_AUTH_TOKEN:-}" ] && [ -z "''${PROJECT_SKIP_REPO_CONTENTS:-}" ]; then
                    echo "Downloading current list of cached contents"
                    curl -H "Authorization: Bearer $CACHIX_AUTH_TOKEN" \
                      "https://app.cachix.org/api/v1/cache/''${CACHIX_REPO}/contents" |\
                        jq -r .[] > prev-cache.txt
                  else
                    echo "Starting without cached contents"
                    touch prev-cache.txt
                  fi
                fi
              }

              # Check if $1 is known as cached
              function known-cached() {
                ( grep "$1" "''${PROJECT_HOME}/cached.txt" || grep "$1" "''${PROJECT_WD}/prev-cache.txt" ) >/dev/null 2>/dev/null
              }

              # Check if $1 is in the cache
              function cached() {
                ( curl -s -o /dev/null -w "%{http_code}" -I "$1/$2.narinfo" | grep -qv '^404$') 2>/dev/null
              }

              # Helper to zip-merge _ALL_OUT_KEYS and _ALL_OUT_PATHS
              function zip_path() {
                for (( i=0; i<''${#_ALL_OUT_KEYS[*]}; ++i)); do
                  echo "''${PROJECT_PREFIX:-}''${_ALL_OUT_KEYS[$i]}" "''${_ALL_OUT_PATHS[$i]}"
                done
              }

              # Per-derivation build function
              function build() {
                _FULL_TARGETS=("''${_ALL_OUT_KEYS[@]/#/$PROJECT_SOURCE\#unrestrictedPackages.''${PROJECT_TARGET}.}")

                # If PROJECT_CHANGED_ONLY is set, only build changed derivations
                if [ -f filter.txt ] && ! grep -Pq "^$_WHAT\$" filter.txt; then
                  return 0
                fi

                # Announce
                echo -n "* $_WHAT..."

                # If previosuly cached
                if [ -z "''${PROJECT_REBUILD_ALL:-}" ] && known-cached "$_MAIN_OUT_PATH"; then
                  echo "$_WHAT" >> cached.txt
                  echo -e "''${Y} CACHED''${W}"
                  zip_path >> full-pin.txt
                  return 0

                # If found in our's cache
                elif [ -z "''${PROJECT_REBUILD_ALL:-}" ] && cached "https://''${CACHIX_REPO}.cachix.org" "$_MAIN_OUT_HASH"; then
                  echo "$_WHAT" >> cached.txt
                  echo "$_MAIN_OUT_PATH" >> "''${PROJECT_HOME}/cached.txt"
                  echo -e "''${Y} CACHED''${W}"
                  zip_path >> full-pin.txt
                  return 0

                # If found in Nixpkgs's cache
                elif cached 'https://cache.nixos.org' "$_MAIN_OUT_HASH"; then
                  echo "$_WHAT" >> upstream.txt
                  echo "$_MAIN_OUT_PATH" >> "''${PROJECT_HOME}/cached.txt"
                  echo -e "''${Y} CACHED-UPSTREAM''${W}"
                  return 0

                # If gently-aborting all builds
                elif [ -e "$PROJECT_WD/abort" ]; then
                  echo -e "''${R} GENTLY ABORTED''${W}"
                  return 1

                # No remaining exceptions let's build
                else
                  # Notifies (inline) the user about building process while also keeping the GitHub Action alive
                  (while true; do echo -ne "''${C} BUILDING''${W}\n* $_WHAT..." && sleep 120; done) &
                  _KEEPALIVE=$!

                  echo '---' >> errors.txt
                  echo "env ''${PROJECT_ENV[*]} nix build --json $PROJECT_FLAGS ''${_FULL_TARGETS[*]}" >> errors.txt
                  # Builds all the outputs, redirect the build logs to "error.txt", redirect the built outputs to "push.txt" (to later push)
                  if \
                    ( env "''${PROJECT_ENV[@]}" nix build --json $PROJECT_FLAGS "''${_FULL_TARGETS[@]}" |\
                        jq -r '.[].outputs[]' \
                    ) 2>> errors.txt >> push.txt

                  # If the build succeeds
                  then
                    # Adds to success list
                    echo "$_WHAT" >> success.txt

                    # Stops the "BUILDING" message
                    kill $_KEEPALIVE

                    # Notify (inline) success
                    echo -e "''${G} OK''${W}"

                    # Add thes "key.$out $outPath" to "to-pin.txt" (to later pin)
                    _TO_PIN=$(zip_path)
                    echo $_TO_PIN | tee -a to-pin.txt >> full-pin.txt

                    # If PROJECT_PUSH_ALL, push & pin it here and now
                    if [ -n "''${PROJECT_PUSH_ALL:-}" ] && ([ -n "''${CACHIX_AUTH_TOKEN:-}" ] || [ -n "''${CACHIX_SIGNING_KEY:-}" ]); then
                      sleep 1
                      cachix push "$CACHIX_REPO" "''${_ALL_OUT_PATHS[@]}"
                      echo $_TO_PIN | xargs -n 2 \
                        cachix -v pin "$CACHIX_REPO" --keep-revisions 7
                      printf '%s\n' "''${_ALL_OUT_PATHS[@]}" >> "''${PROJECT_HOME}/cached.txt"
                    fi

                    # Ends it, successfully, here
                    return 0

                  # If the build fails
                  else
                    # Stops the "BUILDING" message
                    kill $_KEEPALIVE

                    # Notify (inline) failure
                    echo -e "''${R} ERR''${W}"

                    # Ends it, with failure, here
                    return 1
                  fi
                fi
              }

              # Registers that a new package failed
              function failure() {
                # Duplicated package
                if [ -n "$_PREV" ]; then
                  return 0
                fi

                # Add it to failures list
                echo "$_WHAT" >> failures.txt

                # Add it to the know-failures list (to skip it in later builds)
                if [ -z "$_KNOWN_ISSUE" ]; then
                  echo "  \"$_WHAT\" = \"$_MAIN_OUT_PATH\";" >> new-failures.nix
                else
                  echo "  \"$_WHAT\" = \"$_KNOWN_ISSUE\";" >> new-failures.nix
                fi
              }

              # Run when building finishes, before deploying
              function finish() {
                # Write EOF of the artifacts
                echo "}" >> new-failures.nix
              }

              # When you need to exit on failures
              function no-fail() {
                if [ ! $(cat failures.txt | wc -l) -eq 0 ]; then
                  exit 43
                fi

                return 0
              }

              # Push logic
              function deploy() {
                if [ "''${PROJECT_CACHIX_PUSH:-true}" = "false" ]; then
                  echo "Skipping cachix push as PROJECT_CACHIX_PUSH is set to false."
                  return 0
                elif [ -z "''${CACHIX_AUTH_TOKEN:-}" ] && [ -z "''${CACHIX_SIGNING_KEY:-}" ]; then
                  echo_error "No key for cachix -- failing to deploy."
                  exit 23
                elif [ -n "''${PROJECT_PUSH_ANYWAY:-}" ] || [ -s push.txt ]; then
                  # Let nix digest store paths first
                  sleep 10

                  # Push all new deriations with compression
                  cat push.txt | cachix push "$CACHIX_REPO"

                  # Pin packages
                  if [ -e to-pin.txt ]; then
                    cat to-pin.txt | xargs -n 2 \
                      cachix -v pin "$CACHIX_REPO" --keep-revisions 7
                  fi

                  # Locally tag everything as cached
                  cat push.txt >> "''${PROJECT_HOME}/cached.txt"
                else
                  echo_error "Nothing to push."
                  exit 42
                fi
              }

              # Build jobs
              function build-jobs() {
                set +u
                ${lib.strings.concatStringsSep "\n" packagesCmds}

                return 0
              }

              # Phases system
              function default-phases () {
                prepare
                build-jobs
                finish
                deploy
              }
              PHASES=''${PHASES:-default-phases};
              for phase in $PHASES; do $phase; done

              # Useless exit but informative when running with "bash -x"
              exit 0
            '';
        in
        {
          default = mkShell {
            buildInputs = [ builder ];
          };
          dry-build = mkShell {
            env.PROJECT_DRY_BUILD = dry-build;
            shellHook = "echo $PROJECT_DRY_BUILD";
          };

          evaluator = mkShell {
            env.PROJECT_EVALUATED = evaluated;
            shellHook = "echo $PROJECT_EVALUATED";
          };

          updater = mkShell {
            buildInputs = [ bumper ];
          };
        });

      # Generate formatter for all systems
      formatter = forAllSystems (system: (getPkgs system).nixfmt-tree.override {
        settings = {
          tree-root-file = ".git/index";
          excludes = [ ];
          formatter.nixfmt = {
            command = "nixfmt";
            includes = [ "*.nix" ];
          };
        };
      });

      # Also expose the utilities directly
      inherit utils;
    };
}
