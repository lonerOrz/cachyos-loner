{
  description = "Nix flake for linux_cachyos.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }@inputs:
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
                inherit final prev;
              }
              // attrs
            );

          dropUpdate =
            pkg:
            let
              overridden = pkg.overrideAttrs (prevAttrs: {
                passthru = (prevAttrs.passthru or { }) // {
                  autoUpdate = false;
                  updateScript = null;
                };
              });
            in
            overridden // (if pkg ? open then { open = dropUpdate pkg.open; } else { });

          registry = import ./variant-registry.nix {
            inherit
              lib
              final
              prev
              cachyosPackages
              callOverride
              dropUpdate
              ;
          };
        in
        registry;

      utils = import ./utils.nix {
        inherit lib nixpkgs;
      };

      # Overlay evaluation: compute once per system, shared by packages + legacyPackages.
      # Returns only the overlay's own packages (not all of nixpkgs).
      overlayFor =
        system:
        let
          pkgs = utils.getPkgs system;
          ourPackages = defaultOverlay overlayFinal pkgs;
          overlayFinal = (ourPackages // pkgs) // {
            callPackage = pkgs.newScope overlayFinal;
          };
        in
        ourPackages;

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

      treefmtEval =
        system:
        let
          pkgs = utils.getPkgs system;
        in
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.shfmt.enable = true;
          programs.black.enable = true;
          programs.prettier.enable = true;
        };
    in
    {
      overlays.default = defaultOverlay;

      packages = forAllSystems (
        system:
        let
          overlayPkgs = overlayFor system;
        in
        lib.filterAttrs (_: v: (builtins.tryEval v).success && lib.isDerivation v) overlayPkgs
      );

      legacyPackages = forAllSystems (
        system:
        let
          overlayPkgs = overlayFor system;
        in
        lib.filterAttrs (n: _: lib.strings.hasPrefix "linuxPackages_cachyos-" n) overlayPkgs
      );

      needCacheDrvs = forAllSystems (system: import ./need-cache-drvs.nix { inherit self lib system; });

      apps = forAllSystems (system: {
        update = updateApp system;
      });

      formatter = forAllSystems (system: (treefmtEval system).config.build.wrapper);

      checks = forAllSystems (system: {
        formatting = (treefmtEval system).config.build.check self;
      });
    };
}
