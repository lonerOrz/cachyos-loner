{
  final,
  lib,
  pkgsLLVM,
  ltoVars,
  ltsVars,
  rcVars,
  serverVars,
  hardenedVars,
  mainVersions,
  ltsVersions,
  rcVersions,
  serverVersions,
  hardenedVersions,
  preventBuildingKernelModules,
  ...
}:

let
  # Shared configuration template for all LLVM/Clang Thin-LTO flavors.
  ltoKernelAttrs = {
    taste = "linux-cachyos";
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
in
{
  # 1. Mainline GCC flavor (primary update driver for mainline versions.json).
  gcc = {
    taste = "linux-cachyos";
    configPath = ./config-nix/cachyos-gcc.x86_64-linux.nix;
    nvidiaVariant = "stable";
    cachyVars = ltoVars // {
      "_use_llvm_lto" = "none";
    };
    versions = mainVersions;
    updateConfig = {
      versionsFile = "versions.json";
      suffix = "";
      flavors = [
        "-gcc"
        "-lto"
      ];
    };
  };

  # 2. Mainline LLVM Thin-LTO flavor.
  lto = ltoKernelAttrs // {
    configPath = ./config-nix/cachyos-lto.x86_64-linux.nix;
    nvidiaVariant = "stable";
    cachyVars = ltoVars;
    versions = mainVersions;
  };

  # 3. Zen4 optimized LLVM Thin-LTO flavor.
  "lto-znver4" = ltoKernelAttrs // {
    configPath = ./config-nix/cachyos-znver4.x86_64-linux.nix;
    nvidiaVariant = "stable";
    cachyVars = ltoVars // {
      "_processor_opt" = "ZEN4";
    };
    versions = mainVersions;
    packagesExtend = preventBuildingKernelModules;
  };

  # 4. Long-Term Support (LTS) flavor.
  lts = {
    taste = "linux-cachyos-lts";
    configPath = ./config-nix/cachyos-lts.x86_64-linux.nix;
    nvidiaVariant = "lts";
    cachyVars = ltsVars;
    versions = ltsVersions;
    updateConfig = {
      versionsFile = "versions-lts.json";
      suffix = "-lts";
      flavors = [ "-lts" ];
    };
    packagesExtend = preventBuildingKernelModules;
  };

  # 5. Release Candidate (RC) flavor.
  rc = {
    taste = "linux-cachyos-rc";
    configPath = ./config-nix/cachyos-rc.x86_64-linux.nix;
    nvidiaVariant = "rc";
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

  # 6. Server-targeted flavor with DAMON memory reclamation.
  server = {
    taste = "linux-cachyos-server";
    configPath = ./config-nix/cachyos-server.x86_64-linux.nix;
    nvidiaVariant = "server";
    cachyVars = serverVars // {
      _preempt = "server";
      _per_gov = "yes";
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

  # 7. Security-hardened kernel flavor.
  hardened = {
    taste = "linux-cachyos-hardened";
    configPath = ./config-nix/cachyos-hardened.x86_64-linux.nix;
    nvidiaVariant = "hardened";
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
