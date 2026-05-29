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

      defaultOverlay = final: prev:
      let
        # Required to load version files.
        inherit (final.lib.trivial) importJSON;

        projectUtils = import ./utils.nix { lib = final.lib; inherit nixpkgs defaultOverlay; };
        inherit (projectUtils) multiOverride;

        cachyosPackages = import ./pkgs/linux-cachyos {
          inherit final projectUtils prev;
          flakes = inputs;
        };

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

      utils = import ./utils.nix { lib = nixpkgs.lib; inherit nixpkgs defaultOverlay; };

    in
    {
      overlays.default = defaultOverlay;

      packages = forAllSystems (
        system:
        utils.applyOverlay {
          pkgs = utils.getPkgs system;
          onlyDerivations = true;
        }
      );

      legacyPackages = forAllSystems (
        system:
        utils.applyOverlay {
          pkgs = utils.getPkgs system;
        }
      );

      formatter = forAllSystems (system: (utils.getPkgs system).nixfmt-tree.override {
        settings = {
          tree-root-file = ".git/index";
          excludes = [ ];
          formatter.nixfmt = {
            command = "nixfmt";
            includes = [ "*.nix" ];
          };
        };
      });

      inherit utils;
    };
}
