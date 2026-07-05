{
  stdenv,
  taste,
  configPath,
  versions,
  callPackage,
  linuxPackages,
  linuxPackagesFor,
  fetchFromGitHub,
  utils,
  lib,
  buildPackages,
  llvmPackages,
  rustc,
  rust-bindgen,
  rustPlatform,
  ogKernelConfigfile ? linuxPackages.kernel.passthru.configfile,
  updateConfig ? null,
  packagesExtend ? null,
  cachyOverride,
  extraMakeFlags ? [ ],
  zfsOverride ? { },
  cachyVars,
  withPrivateHDR ? false,
  withDAMON ? false,
  withNTSync ? true,
  description ? "Linux EEVDF-BORE scheduler Kernel by CachyOS with other patches and improvements",
  inputs,
}:

let
  yesOrNo =
    str:
    if str == "yes" then
      true
    else if str == "no" then
      false
    else
      throw "Unsupported yes/no value";

  nullIfEmpty = str: if str == "" then null else str;

  # Config vars that are Nix-incompatible (need interactive TUI/GUI, running system, or /proc):
  #   _makenconfig, _makexconfig, _localmodcfg, _localmodcfg_path, _use_current
  # Config vars handled elsewhere (overlay suffix or separate packages):
  #   _use_lto_suffix, _use_gcc_suffix, _build_zfs, _build_nvidia_open, _build_r8125
  cachyConfig = {
    inherit
      taste
      versions
      cachyVars
      withPrivateHDR
      withDAMON
      withNTSync
      description
      ;

    basicCachy = yesOrNo cachyVars."_cachy_config";
    mArch = nullIfEmpty cachyVars."_processor_opt";
    cpuSched = cachyVars."_cpusched";
    ccHarder = yesOrNo cachyVars."_cc_harder";
    perGov = yesOrNo cachyVars."_per_gov";
    tcpBBR3 = yesOrNo cachyVars."_tcp_bbr3";
    useLTO = cachyVars."_use_llvm_lto";
    useKCFI = yesOrNo cachyVars."_use_kcfi";
    ticksHz = lib.strings.toInt cachyVars."_HZ_ticks";
    tickRate = cachyVars."_tickrate";
    preempt = cachyVars."_preempt";
    hugePages = cachyVars."_hugepage";
    autoFDO = yesOrNo (cachyVars."_autofdo" or "no");
    autoFDOProfileName = cachyVars."_autofdo_profile_name" or "";
    propeller = yesOrNo (cachyVars."_propeller" or "no");
    propellerProfiles = cachyVars."_propeller_profiles" or "no";
    withoutDebug = !(yesOrNo (cachyVars."_build_debug" or "no"));
  };

  dropAttrsUpdateScript = builtins.mapAttrs (
    _k: v:
    if (v.passthru.updateScript or null) != null then
      v.overrideAttrs (prevAttrs: {
        passthru = removeAttrs prevAttrs.passthru [ "updateScript" ];
      })
    else
      v
  );

  # The three phases of the config
  # - First we apply the changes from their PKGBUILD using kconfig;
  # - Then we NIXify it (in the update-script);
  # - Last state is importing the NIXified version for building.
  preparedConfigfile = callPackage ./prepare.nix {
    inherit
      cachyConfig
      stdenv
      kernel
      ogKernelConfigfile
      commonMakeFlags
      ;
  };
  kconfigToNix = inputs.final.callPackage ./lib/kconfig-to-nix.nix {
    configfile = preparedConfigfile;
  };
  linuxConfigTransformed = import configPath;

  commonMakeFlagsBintools =
    import "${inputs.flakes.nixpkgs}/pkgs/os-specific/linux/kernel/common-flags.nix"
      {
        inherit
          lib
          stdenv
          buildPackages
          ;
        extraMakeFlags = if cachyConfig.useLTO == "none" then extraMakeFlags else [ ];
      };

  commonMakeFlags =
    if cachyConfig.useLTO != "none" then
      lib.trivial.pipe commonMakeFlagsBintools [
        (utils.replaceStartingWith "LD=" (lib.getExe' llvmPackages.lld "ld.lld"))
        (utils.replaceStartingWith "AR=" (lib.getExe' llvmPackages.llvm "llvm-ar"))
        (utils.replaceStartingWith "NM=" (lib.getExe' llvmPackages.llvm "llvm-nm"))
      ]
      ++ [
        "RUSTC=${lib.getExe' rustc "rustc"}"
        "BINDGEN=${lib.getExe rust-bindgen}"
        "RUST_LIB_SRC=${rustPlatform.rustLibSrc}"
      ]
      ++ extraMakeFlags
    else
      commonMakeFlagsBintools;

  kernel = callPackage ./kernel.nix {
    inherit
      cachyConfig
      stdenv
      kconfigToNix
      commonMakeFlags
      ;
    kernelPatches = [ ];
    configfile = preparedConfigfile;
    config = linuxConfigTransformed;
    # For tests
    inherit (inputs) flakes final;
    kernelPackages = basePackages;
  };

  kernelWithUpdateScript = kernel.overrideAttrs (prevAttrs: {
    passthru = prevAttrs.passthru // {
      updateScript =
        if updateConfig != null then
          inputs.final.callPackage ./update.nix { inherit updateConfig; }
        else
          inputs.final.writeShellScriptBin "update-cachyos" ''
            echo "${taste}: No independent updateScript. Please run the updateScript for linux_cachyos-gcc instead."
          '';
    };
  });

  # CachyOS repeating stuff.
  addOurs = finalAttrs: prevAttrs: {
    kernel_configfile = prevAttrs.kernel.configfile;
    zfs_cachyos =
      (finalAttrs.callPackage "${inputs.flakes.nixpkgs}/pkgs/os-specific/linux/zfs/generic.nix"
        zfsOverride
        {
          kernelModuleAttribute = "zfs_cachyos";
          kernelMinSupportedMajorMinor = "1.0";
          kernelMaxSupportedMajorMinor = "99.99";
          enableUnsupportedExperimentalKernel = true;
          inherit (prevAttrs.zfs_2_4) version;
          tests = { };
          maintainers = with lib.maintainers; [
            pedrohlc
          ];
          hash = "";
          extraPatches = [ ];
        }
      ).overrideAttrs
        (prevAttrs: {
          src = fetchFromGitHub {
            owner = "cachyos";
            repo = "zfs";
            inherit (versions.zfs) rev hash;
          };
          postPatch = builtins.replaceStrings [ "grep --quiet '^Linux-M" ] [ "# " ] prevAttrs.postPatch;
        });
    nvidiaPackages = prevAttrs.nvidiaPackages.extend (
      _finalNV: _prevNV: {
        cachyos =
          let
            suffix = lib.strings.removePrefix "linux-cachyos" taste;
            attrName = "nvidia_cachyos${suffix}";
          in
          if inputs.final ? ${attrName} then
            let
              tryEval = builtins.tryEval inputs.final.${attrName};
            in
            if tryEval.success then tryEval.value else null
          else
            null;
      }
    );
    inherit cachyOverride;
  };

  llvmModuleOverlay = import ./lib/llvm-module-overlay.nix inputs;

  basePackages = linuxPackagesFor kernelWithUpdateScript;
  packagesWithOurs = basePackages.extend addOurs;
  packagesWithLtoModuleOverlay =
    if cachyConfig.useLTO != "none" then
      packagesWithOurs.extend (llvmModuleOverlay kernel)
    else
      packagesWithOurs;
  packagesWithExtend =
    if packagesExtend == null then
      packagesWithLtoModuleOverlay
    else
      packagesWithLtoModuleOverlay.extend (packagesExtend kernel);
  packagesWithRemovals = removeAttrs packagesWithExtend [
    "zfs"
    "zfs_2_1"
    "zfs_2_2"
    "zfs_2_3"
    "zfs_2_4"
    "zfs_unstable"
    "lkrg"
    "drbd"
    # these kernelPackages.* are now pkgs.*
    "system76-power"
    "system76-scheduler"
    "perf"
  ];
  supportedPlatforms = [
    (with lib.systems.inspect.patterns; isx86_64 // isLinux)
    (with lib.systems.inspect.patterns; isx86 // isLinux)
    "x86_64-linux"
  ];

  packagesWithoutUpdateScript = dropAttrsUpdateScript packagesWithRemovals;
  packagesWithRightPlatforms = builtins.mapAttrs (
    _k: v:
    if (v ? "overrideAttrs") then
      v.overrideAttrs (prevAttrs: {
        meta = (prevAttrs.meta or { }) // {
          platforms = lib.lists.intersectLists (prevAttrs.meta.platforms or [ ]) supportedPlatforms;
          platformsOrig = prevAttrs.meta.platforms or [ ];
          badPlatforms = [ ];
        };
      })
    else
      v
  ) packagesWithoutUpdateScript;

  versionSuffix = "+C${builtins.substring 0 7 versions.config.rev}+P${builtins.substring 0 7 versions.patches.rev}";
in
packagesWithRightPlatforms
// {
  _description = "Kernel and modules for ${description}";
  _version = "${versions.linux.version}${versionSuffix}";
  inherit (basePackages) kernel; # This one still has the updateScript
}
