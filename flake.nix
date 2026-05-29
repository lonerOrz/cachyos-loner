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

            # Helps when batch-overriding.
            dropAttrsUpdateScript = builtins.mapAttrs (
              _k: v: if (v.passthru.updateScript or null) != null then v.overrideAttrs dropUpdateScript else v
            );

            # Helps when overriding.
            dropUpdateScript = prevAttrs: { passthru = removeAttrs prevAttrs.passthru [ "updateScript" ]; };

            # Helps when overriding.
            drvDropUpdateScript = package: package.overrideAttrs dropUpdateScript;

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
            removeByURL = url: builtins.filter (x: !(lib.attrsets.isDerivation x) || (x.url or null) != url);

            # Helps when dropping flags.
            removeByPrefix =
              prefix:
              let
                prefixLen = builtins.stringLength prefix;
              in
              builtins.filter (s: builtins.substring 0 prefixLen s != prefix);

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

      # Define utility functions (only applyOverlay is needed here;
      # projectUtils in the overlay provides the rest)
      utils = rec {
        applyOverlay =
          {
            replace ? false,
            merge ? false,
            overlay ? defaultOverlay,
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
