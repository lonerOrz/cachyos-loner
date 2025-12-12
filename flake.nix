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

      # Import all dev shells once
      allDevShells = import ./dev-shells.nix { flakes = inputs; };

      # Define the main overlay
      defaultOverlay = import ./overlays { flakes = inputs; };

      # Define utility functions
      utils = import ./shared/utils.nix {
        projectOverlay = defaultOverlay;
        inherit (nixpkgs) lib;
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
      devShells = forAllSystems (system: allDevShells.${system});

      # Generate formatter for all systems
      formatter = forAllSystems (system: import ./formatter.nix (getPkgs system));

      # Also expose the utilities directly
      inherit utils;
    };
}
