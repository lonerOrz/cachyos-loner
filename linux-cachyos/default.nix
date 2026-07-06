{
  final,
  ...
}@inputs:

let
  inherit (final.stdenv) isx86_64 isLinux;
  inherit (final.lib.trivial) importJSON;

  utils = import ../utils.nix { lib = final.lib; };

  # CachyOS repeating stuff
  mainVersions = importJSON ./versions.json;
  hardenedVersions = importJSON ./versions-hardened.json;
  ltsVersions = importJSON ./versions-lts.json;
  rcVersions = importJSON ./versions-rc.json;
  serverVersions = importJSON ./versions-server.json;
  hardenedVars = importJSON ./config-vars/cachyos-hardened.json;
  ltoVars = importJSON ./config-vars/cachyos-lto.json;
  ltsVars = importJSON ./config-vars/cachyos-lts.json;
  rcVars = importJSON ./config-vars/cachyos-rc.json;
  serverVars = importJSON ./config-vars/cachyos-server.json;

  # Clang/LTO things
  pkgsLLVM = import ./lib/llvm-pkgs.nix inputs;

  ltoKernelAttrs = {
    taste = "linux-cachyos";
    configPath = ./config-nix/cachyos-lto.x86_64-linux.nix;
    cachyVars = ltoVars;

    inherit (pkgsLLVM) callPackage;
    stdenv = pkgsLLVM.clangStdenv;

    zfsOverride = {
      inherit (final)
        autoreconfHook269
        util-linux
        coreutils
        perl
        udevCheckHook
        zlib
        libuuid
        python3
        attr
        openssl
        libtirpc
        nfs-utils
        gawk
        gnugrep
        gnused
        systemd
        smartmontools
        sysstat
        pkg-config
        curl
        pam
        nix-update-script
        ;
    };

    description = "Linux EEVDF-BORE scheduler Kernel by CachyOS built with LLVM and Thin LTO";
  };

  # Evaluation hack
  brokenReplacement = final.hello.overrideAttrs (prevAttrs: {
    meta = prevAttrs.meta // {
      platform = [ ];
      broken = true;
    };
  });

  isUnsupported = !isx86_64 || !isLinux;

  mkCachyKernel =
    if isUnsupported then
      # Evaluation hack
      _attrs: {
        kernel = brokenReplacement;
        recurseForDerivations = false;
      }
    else
      {
        callPackage ? final.callPackage,
        ...
      }@attrs:
      callPackage ./packages-for.nix (
        {
          versions = mainVersions;
          inherit inputs utils;
          cachyOverride = newAttrs: mkCachyKernel (attrs // newAttrs);
        }
        // attrs
      );

  gccKernel = mkCachyKernel {
    taste = "linux-cachyos";
    configPath = ./config-nix/cachyos-gcc.x86_64-linux.nix;

    cachyVars = ltoVars // {
      "_use_llvm_lto" = "none";
    };

    updateConfig = {
      versionsFile = "versions.json";
      suffix = "";
      flavors = [
        "-gcc"
        "-lto"
      ];
    };
  };

  preventBuildingKernelModules =
    _kernel: _final: prev:
    prev // { recurseForDerivations = false; };
in
{
  cachyos-gcc = gccKernel;

  cachyos-sched-ext = throw "\"sched-ext\" patches were merged with \"cachyos\" flavor.";

  cachyos-lts = mkCachyKernel {
    taste = "linux-cachyos-lts";
    configPath = ./config-nix/cachyos-lts.x86_64-linux.nix;
    cachyVars = ltsVars;

    versions = ltsVersions;
    updateConfig = {
      versionsFile = "versions-lts.json";
      suffix = "-lts";
      flavors = [ "-lts" ];
    };

    packagesExtend = preventBuildingKernelModules;
  };

  cachyos-rc = mkCachyKernel {
    taste = "linux-cachyos-rc";
    configPath = ./config-nix/cachyos-rc.x86_64-linux.nix;
    cachyVars = rcVars // {
      "_use_llvm_lto" = "none";
    };

    versions = rcVersions;
    updateConfig = {
      versionsFile = "versions-rc.json";
      suffix = "-rc";
      flavors = [ "-rc" ];
    };

    packagesExtend = preventBuildingKernelModules;
  };

  cachyos-lto = mkCachyKernel ltoKernelAttrs;

  cachyos-lto-znver4 = mkCachyKernel (
    ltoKernelAttrs
    // {
      configPath = ./config-nix/cachyos-znver4.x86_64-linux.nix;
      cachyVars = ltoVars // {
        _processor_opt = "ZEN4";
      };

      packagesExtend = preventBuildingKernelModules;
    }
  );

  cachyos-server = mkCachyKernel {
    taste = "linux-cachyos-server";
    configPath = ./config-nix/cachyos-server.x86_64-linux.nix;
    cachyVars = serverVars // {
      "_preempt" = "server";
      "_per_gov" = "yes";
    };

    versions = serverVersions;
    updateConfig = {
      versionsFile = "versions-server.json";
      suffix = "-server";
      flavors = [ "-server" ];
    };

    withDAMON = true;
    withNTSync = false;
    withPrivateHDR = false;

    description = "Linux EEVDF scheduler Kernel by CachyOS targeted for Servers";

    packagesExtend = preventBuildingKernelModules;
  };

  cachyos-hardened = mkCachyKernel {
    taste = "linux-cachyos-hardened";
    configPath = ./config-nix/cachyos-hardened.x86_64-linux.nix;
    cachyVars = hardenedVars;

    versions = hardenedVersions;
    updateConfig = {
      versionsFile = "versions-hardened.json";
      suffix = "-hardened";
      flavors = [ "-hardened" ];
    };

    withNTSync = false;
    withPrivateHDR = false;

    packagesExtend = preventBuildingKernelModules;
  };
}
