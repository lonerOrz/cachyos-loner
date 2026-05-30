{
  final,
  ...
}@inputs:

let
  inherit (final.stdenv) isx86_64 isLinux;

  versions = {
    main = builtins.fromJSON (builtins.readFile ./versions.json);
    server = builtins.fromJSON (builtins.readFile ./versions-server.json);
    lts = builtins.fromJSON (builtins.readFile ./versions-lts.json);
    rc = builtins.fromJSON (builtins.readFile ./versions-rc.json);
    hardened = builtins.fromJSON (builtins.readFile ./versions-hardened.json);
  };

  ltoBase = {
    taste = "linux-cachyos";
    configPath = ./config-nix/cachyos-lto.x86_64-linux.nix;

    inherit (import ./lib/llvm-pkgs.nix inputs) callPackage;
    useLTO = "thin";
    stdenv = final.clangStdenv;

    packagesExtend = import ./lib/llvm-module-overlay.nix inputs;

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

  isUnsupported = !isx86_64 || !isLinux;

  brokenReplacement = final.hello.overrideAttrs (prevAttrs: {
    meta = prevAttrs.meta // {
      platform = [ ];
      broken = true;
    };
  });

  mkCachyKernel =
    if isUnsupported then
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
          versions = versions.main;
          inherit inputs;
          cachyOverride = newAttrs: mkCachyKernel (attrs // newAttrs);
        }
        // attrs
      );

  # Reference needed for zfs derivation below
  gccPackages = mkCachyKernel {
    taste = "linux-cachyos";
    configPath = ./config-nix/cachyos-gcc.x86_64-linux.nix;
    updateConfig = {
      versionsFile = "versions.json";
      suffix = "";
      flavors = [
        "-gcc"
        "-lto"
      ];
    };
  };
in
{
  cachyos-gcc = gccPackages;

  cachyos-lto = mkCachyKernel (
    ltoBase
    // {
      updateConfig = null;
    }
  );

  cachyos-lto-znver4 = mkCachyKernel (
    ltoBase
    // {
      configPath = ./config-nix/cachyos-znver4.x86_64-linux.nix;
      updateConfig = null;
    }
  );

  cachyos-sched-ext = throw "\"sched-ext\" patches were merged with \"cachyos\" flavor.";

  cachyos-server = mkCachyKernel {
    taste = "linux-cachyos-server";
    configPath = ./config-nix/cachyos-server.x86_64-linux.nix;
    basicCachy = false;
    cpuSched = "eevdf";
    ticksHz = 300;
    tickRate = "idle";
    preempt = "server";
    hugePages = "madvise";
    withDAMON = true;
    withNTSync = false;
    withHDR = false;
    description = "Linux EEVDF scheduler Kernel by CachyOS targeted for Servers";
    versions = versions.server;
    updateConfig = {
      versionsFile = "versions-server.json";
      suffix = "-server";
      flavors = [ "-server" ];
    };
  };

  cachyos-lts = mkCachyKernel {
    taste = "linux-cachyos-lts";
    configPath = ./config-nix/cachyos-lts.x86_64-linux.nix;

    versions = versions.lts;
    updateConfig = {
      versionsFile = "versions-lts.json";
      suffix = "-lts";
      flavors = [ "-lts" ];
    };

    packagesExtend =
      _kernel: _final: prev:
      prev // { recurseForDerivations = false; };
  };

  cachyos-rc = mkCachyKernel {
    taste = "linux-cachyos-rc";
    configPath = ./config-nix/cachyos-rc.x86_64-linux.nix;

    versions = versions.rc;
    updateConfig = {
      versionsFile = "versions-rc.json";
      suffix = "-rc";
      flavors = [ "-rc" ];
    };

    packagesExtend =
      _kernel: _final: prev:
      prev // { recurseForDerivations = false; };
  };

  cachyos-hardened = mkCachyKernel {
    taste = "linux-cachyos-hardened";
    configPath = ./config-nix/cachyos-hardened.x86_64-linux.nix;
    cpuSched = "hardened";

    versions = versions.hardened;
    updateConfig = {
      versionsFile = "versions-hardened.json";
      suffix = "-hardened";
      flavors = [ "-hardened" ];
    };

    withNTSync = false;
    withHDR = false;
  };

  zfs = final.zfs_2_3.overrideAttrs (prevAttrs: {
    src = if isUnsupported then brokenReplacement else gccPackages.zfs_cachyos.src;
    patches = [ ];
    passthru = prevAttrs.passthru // {
      kernelModuleAttribute = "zfs_cachyos";
    };
    postPatch = builtins.replaceStrings [ "grep --quiet '^Linux-M" ] [ "# " ] prevAttrs.postPatch;
  });
}
