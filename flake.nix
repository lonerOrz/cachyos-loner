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
            inherit lib final prev cachyosPackages callOverride dropUpdate;
          };
        in
        registry;

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

      legacyPackages = forAllSystems (
        system:
        let
          overlayPkgs = utils.applyOverlay {
            pkgs = utils.getPkgs system;
            onlyDerivations = false;
          };
        in
        {
          linuxPackages_cachyos-gcc = overlayPkgs.linuxPackages_cachyos-gcc;
          linuxPackages_cachyos-lto = overlayPkgs.linuxPackages_cachyos-lto;
          linuxPackages_cachyos-lto-znver4 = overlayPkgs.linuxPackages_cachyos-lto-znver4;
          linuxPackages_cachyos-server = overlayPkgs.linuxPackages_cachyos-server;
          linuxPackages_cachyos-hardened = overlayPkgs.linuxPackages_cachyos-hardened;
          linuxPackages_cachyos-rc = overlayPkgs.linuxPackages_cachyos-rc;
          linuxPackages_cachyos-lts = overlayPkgs.linuxPackages_cachyos-lts;
        }
      );

      needCacheDrvs = forAllSystems (
        system:
        let
          pkgs = self.packages.${system};
          linuxPkgs = self.legacyPackages.${system} or { };

          tryDrvPath =
            pkg:
            let r = builtins.tryEval (pkg.drvPath or null);
            in if r.success && r.value != null then r.value else null;

          tryAttr =
            set: attr:
            let r = builtins.tryEval (set.${attr} or null);
            in if r.success then r.value else null;

          isDerivation = x: builtins.isAttrs x && (x.type or null) == "derivation";

          isCoreModule =
            name:
            let has = s: lib.strings.hasInfix s name;
            in (has "nvidia" || has "zfs_cachyos") && !(has "nvidia" && has "linuxPackages");

          extractModuleDrvs =
            variant: mod:
            let
              val = tryAttr linuxPkgs.${variant} mod;
              prefix = "legacyPackages.${system}.${variant}.${mod}";
            in
            if val == null then [ ]
            else if isDerivation val then
              [ { name = prefix; value = tryDrvPath val; } ]
            else if builtins.isAttrs val && !(val ? type) then
              map
                (n: { name = "${prefix}.${n}"; value = tryDrvPath (tryAttr val n); })
                (builtins.filter (n: let v = tryAttr val n; in v != null && isDerivation v) (builtins.attrNames val))
            else [ ];

          flatPackages = lib.genAttrs
            (builtins.attrNames pkgs)
            (name: tryDrvPath pkgs.${name});

          allNested = builtins.listToAttrs (
            lib.concatMap
              (variant:
                let s = linuxPkgs.${variant} or { };
                in if builtins.isAttrs s
                then lib.concatMap (mod: extractModuleDrvs variant mod) (builtins.attrNames s)
                else [ ]
              )
              (builtins.attrNames linuxPkgs)
          );

          all = lib.filterAttrs (_: v: v != null) (flatPackages // allNested);
        in
        {
          kernels = lib.filterAttrs
            (name: _: lib.strings.hasInfix "linux_cachyos" name || lib.strings.hasInfix ".kernel" name)
            all;
          modules = lib.filterAttrs (_: isCoreModule) all;
        }
      );

      apps = forAllSystems (system: {
        update = updateApp system;
      });
    };
}
