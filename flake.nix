{
  description = "Nix flake for linux_cachyos.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);

      defaultOverlay =
        final: prev:
        let
          cachyosPackages = import ./linux-cachyos {
            inherit final prev;
            flakes = inputs;
          };
        in
        {

          linux_cachyos = cachyosPackages.cachyos-gcc.kernel;
          linux_cachyos-lto = cachyosPackages.cachyos-lto.kernel;
          linux_cachyos-lto-znver4 = cachyosPackages.cachyos-lto-znver4.kernel;

          linux_cachyos-gcc = cachyosPackages.cachyos-gcc.kernel;
          linux_cachyos-server = cachyosPackages.cachyos-server.kernel;
          linux_cachyos-hardened = cachyosPackages.cachyos-hardened.kernel;
          linux_cachyos-rc = cachyosPackages.cachyos-rc.kernel;
          linux_cachyos-lts = cachyosPackages.cachyos-lts.kernel;

          linuxPackages_cachyos = cachyosPackages.cachyos-gcc;
          linuxPackages_cachyos-lto = cachyosPackages.cachyos-lto;
          linuxPackages_cachyos-lto-znver4 = cachyosPackages.cachyos-lto-znver4;

          linuxPackages_cachyos-gcc = cachyosPackages.cachyos-gcc;
          linuxPackages_cachyos-server = cachyosPackages.cachyos-server;
          linuxPackages_cachyos-hardened = cachyosPackages.cachyos-hardened;
          linuxPackages_cachyos-rc = cachyosPackages.cachyos-rc;
          linuxPackages_cachyos-lts = cachyosPackages.cachyos-lts;

          zfs_cachyos = cachyosPackages.zfs;
        };

      utils = import ./utils.nix {
        lib = nixpkgs.lib;
        inherit nixpkgs defaultOverlay;
      };

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
    };
}
