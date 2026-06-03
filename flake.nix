{
  description = "Nix flake for linux_cachyos.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs [ "x86_64-linux" ];

      defaultOverlay =
        final: prev:
        let
          cachyosPackages = import ./linux-cachyos {
            inherit final prev;
            flakes = inputs;
          };

          callOverride =
            path: attrs:
            import path (
              {
                inherit final inputs prev;
              }
              // attrs
            );

          dropUpdate =
            pkg:
            pkg.overrideAttrs (prevAttrs: {
              passthru = (prevAttrs.passthru or { }) // {
                autoUpdate = false;
                updateScript = null;
              };
            });
        in
        {
          linux_cachyos = dropUpdate final.linux_cachyos-gcc;
          linux_cachyos-lto = dropUpdate cachyosPackages.cachyos-lto.kernel;
          linux_cachyos-lto-znver4 = dropUpdate cachyosPackages.cachyos-lto-znver4.kernel;

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

          nvidia_cachyos = callOverride ./nvidia-cachyos { };
          nvidia_cachyos-gcc = dropUpdate final.nvidia_cachyos;
          nvidia_cachyos-lto = dropUpdate final.nvidia_cachyos;
          nvidia_cachyos-rc = callOverride ./nvidia-cachyos { variant = "rc"; };
          nvidia_cachyos-server = callOverride ./nvidia-cachyos { variant = "server"; };
          nvidia_cachyos-hardened = callOverride ./nvidia-cachyos { variant = "hardened"; };
          nvidia_cachyos-lts = callOverride ./nvidia-cachyos { variant = "lts"; };

          zfs_cachyos = dropUpdate cachyosPackages.zfs;
        };

      utils = import ./utils.nix {
        inherit lib nixpkgs defaultOverlay;
      };

      updateApp =
        system:
        let
          pkgs = utils.getPkgs system;
          updateScript = pkgs.writeShellApplication {
            name = "update";
            runtimeInputs = with pkgs; [
              python3
              nix-update
              nix-prefetch-git
              git
              curl
              cacert
              jq
              moreutils
              gnused
              gawk
              gnugrep
              findutils
              coreutils
            ];
            text = ''
              export GIT_EDITOR="true"
              export GIT_CONFIG_COUNT="1"
              export GIT_CONFIG_KEY_0="commit.gpgSign"
              export GIT_CONFIG_VALUE_0="false"

              python .github/scripts/update.py "$@"
            '';
          };
        in
        {
          type = "app";
          program = lib.getExe updateScript;
          meta = {
            description = "Update linux-cachyos kernel and module versions";
          };
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

      apps = forAllSystems (system: {
        update = updateApp system;
      });
    };
}
