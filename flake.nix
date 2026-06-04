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

          nvidia_cachyos-open = dropUpdate final.nvidia_cachyos.open;
          nvidia_cachyos-gcc-open = dropUpdate final.nvidia_cachyos-open;
          nvidia_cachyos-lto-open = dropUpdate final.nvidia_cachyos-open;
          nvidia_cachyos-rc-open = dropUpdate final.nvidia_cachyos-rc.open;
          nvidia_cachyos-server-open = dropUpdate final.nvidia_cachyos-server.open;
          nvidia_cachyos-hardened-open = dropUpdate final.nvidia_cachyos-hardened.open;
          nvidia_cachyos-lts-open = dropUpdate final.nvidia_cachyos-lts.open;

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

      linuxPackages = forAllSystems (
        system:
        let
          overlayPkgs = utils.applyOverlay {
            pkgs = utils.getPkgs system;
            onlyDerivations = false;
          };
        in
        {
          cachyos-gcc = overlayPkgs.linuxPackages_cachyos-gcc;
          cachyos-server = overlayPkgs.linuxPackages_cachyos-server;
          cachyos-hardened = overlayPkgs.linuxPackages_cachyos-hardened;
          cachyos-rc = overlayPkgs.linuxPackages_cachyos-rc;
          cachyos-lts = overlayPkgs.linuxPackages_cachyos-lts;
        }
      );

      needCacheDrvs = forAllSystems (
        system:
        let
          pkgs = self.packages.${system};
          linuxPkgs = self.linuxPackages.${system} or { };
          isDerivation = x: builtins.isAttrs x && x ? type && x.type == "derivation";

          # 安全属性读取函数：防御属性读取时的 throw (如 amdgpu-pro)
          safeGetAttr =
            set: attr:
            let
              tryEval = builtins.tryEval set.${attr};
            in
            if tryEval.success then tryEval.value else null;

          # 安全获取 drvPath：防御 drvPath 求值时的 assert (如 broadcom_sta)
          safeGetDrvPath =
            pkg:
            let
              tryEval = builtins.tryEval pkg.drvPath;
            in
            if tryEval.success then tryEval.value else "error";

          # 核心模块白名单
          isCoreModule =
            name:
            (!(lib.strings.hasInfix "nvidia" name) || !(lib.strings.hasInfix "linuxPackages" name))
            && (
              (lib.strings.hasInfix "nvidia" name)
              || (lib.strings.hasInfix "zfs_cachyos" name)
              || (lib.strings.hasInfix "xone" name)
              || (lib.strings.hasInfix "xpadneo" name)
              || (lib.strings.hasInfix "zenpower" name)
              || (lib.strings.hasInfix "v4l2loopback" name)
              || (lib.strings.hasInfix "rtl88" name)
              || (lib.strings.hasInfix "evdi" name)
            );

          allFlat = builtins.mapAttrs (name: value: safeGetDrvPath value) pkgs;

          allNested = builtins.listToAttrs (
            builtins.concatLists (
              map (
                variantName:
                let
                  variantSet = linuxPkgs.${variantName} or { };
                in
                if builtins.isAttrs variantSet then
                  builtins.concatLists (
                    map (
                      moduleName:
                      let
                        moduleVal = safeGetAttr variantSet moduleName;
                        fullName = "linuxPackages.${variantName}.${moduleName}";
                      in
                      if moduleVal == null then
                        [ ]
                      else if isDerivation moduleVal then
                        [
                          {
                            name = fullName;
                            value = safeGetDrvPath moduleVal;
                          }
                        ]
                      else if builtins.isAttrs moduleVal && !(moduleVal ? type) then
                        map (
                          subName:
                          let
                            subVal = safeGetAttr moduleVal subName;
                            subFullName = "linuxPackages.${variantName}.${moduleName}.${subName}";
                          in
                          {
                            name = subFullName;
                            value = safeGetDrvPath subVal;
                          }
                        ) (builtins.filter (n: isDerivation moduleVal.${n}) (builtins.attrNames moduleVal))
                      else
                        [ ]
                    ) (builtins.attrNames variantSet)
                  )
                else
                  [ ]
              ) (builtins.attrNames linuxPkgs)
            )
          );

          allCombined = allFlat // allNested;

          # 剔除无法求值的错误包
          partitioned = lib.filterAttrs (name: value: value != "error") allCombined;
        in
        {
          # 内核本身
          kernels = lib.filterAttrs (
            name: _value: (lib.strings.hasInfix "linux_cachyos" name) || (lib.strings.hasInfix ".kernel" name)
          ) partitioned;

          # 核心驱动与内核模块
          modules = lib.filterAttrs (name: _value: isCoreModule name) partitioned;
        }
      );

      apps = forAllSystems (system: {
        update = updateApp system;
      });
    };
}
