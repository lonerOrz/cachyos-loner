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
          in
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
          };
        inherit (projectUtils) multiOverride;

        cachyosPackages = import ./pkgs/linux-cachyos {
          inherit final projectUtils prev;
          flakes = inputs;
        };

        # Required for kernel packages
        inherit (final.stdenv) isLinux isx86_64;

      in
      {
        inherit projectUtils;

        linux_cachyos = cachyosPackages.cachyos-gcc.kernel;
        linux_cachyos-lto = cachyosPackages.cachyos-lto.kernel;

        linux_cachyos-gcc = cachyosPackages.cachyos-gcc.kernel;
        linux_cachyos-server = cachyosPackages.cachyos-server.kernel;
        linux_cachyos-hardened = cachyosPackages.cachyos-hardened.kernel;
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
