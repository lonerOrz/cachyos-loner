{
  cachyConfig,
  fetchFromGitHub,
  fetchurl,
  lib,
  stdenv,
  kernel,
  ogKernelConfigfile,
  commonMakeFlags,
}:

let
  inherit (cachyConfig.versions.linux) version;
  majorMinor = lib.versions.majorMinor version;

  # Upstream CachyOS patch queue.
  patches-src = fetchFromGitHub {
    owner = "CachyOS";
    repo = "kernel-patches";
    inherit (cachyConfig.versions.patches) rev hash;
  };

  # Upstream CachyOS flavor config repo.
  config-src = fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux-cachyos";
    inherit (cachyConfig.versions.config) rev hash;
  };

  # Fetch pre-sauced CachyOS GitHub release tarball if tagrel is set; fallback to kernel.org.
  src =
    if cachyConfig.versions.linux ? tagrel then
      let
        inherit (cachyConfig.versions.linux) tagrel;
        srctag = "cachyos-${version}-${toString tagrel}";
      in
      fetchurl {
        url = "https://github.com/CachyOS/linux/releases/download/${srctag}/${srctag}.tar.gz";
        inherit (cachyConfig.versions.linux) hash;
      }
    else
      fetchurl {
        url = "mirror://kernel/linux/kernel/v${lib.versions.major version}.x/linux-${
          if version == "${majorMinor}.0" then majorMinor else version
        }.tar.xz";
        inherit (cachyConfig.versions.linux) hash;
      };

  # Resolve an upstream patch only if the patch queue actually ships it for this
  # major.minor; upstream lags on new -rc releases, which must not fail the build.
  upstreamPatch =
    rel:
    let
      p = "${patches-src}/${majorMinor}/${rel}";
    in
    lib.optionals (builtins.pathExists p) [ p ];

  # Select scheduler patches based on configured cpuSched.
  schedPatches =
    if cachyConfig.cpuSched == "eevdf" then
      [ ]
    else if cachyConfig.cpuSched == "hardened" then
      [ ]
    else if cachyConfig.cpuSched == "bore" then
      upstreamPatch "sched/0001-bore-cachy.patch"
    else if cachyConfig.cpuSched == "bmq" then
      upstreamPatch "sched/0001-prjc-cachy.patch"
    else if (cachyConfig.cpuSched == "cachyos" || cachyConfig.cpuSched == "sched-ext") then
      lib.optionals (lib.strings.versionOlder majorMinor "6.12") (
        upstreamPatch "sched/0001-sched-ext.patch"
      )
      ++ lib.optionals (cachyConfig.cpuSched == "cachyos") [
        (
          if lib.versionAtLeast version "6.18.35" && cachyConfig.taste == "linux-cachyos-lts" then
            "${./patches/0001-bore-cachy.patch}"
          else if
            lib.versionAtLeast version "7.2-rc2"
            && lib.versionOlder version "7.3"
            && toString (cachyConfig.versions.linux.tagrel or "") == "3"
            && cachyConfig.taste == "linux-cachyos-rc"
          then
            "${./patches/0001-bore-cachy-rc.patch}"
          else
            "${patches-src}/${majorMinor}/sched/0001-bore-cachy.patch"
        )
      ]
    else if (cachyConfig.cpuSched == "rt-bore") then
      upstreamPatch "sched/0001-bore-cachy.patch" ++ upstreamPatch "misc/0001-rt-i915.patch"
    else if (cachyConfig.cpuSched == "rt") then
      upstreamPatch "misc/0001-rt-i915.patch"
    else
      throw "Unsupported cachyos _cpu_sched=${toString cachyConfig.cpuSched}";

  # Combine base patchset (if not pre-patched in release tarball) with sched and misc patches.
  patches =
    lib.optionals (!(cachyConfig.versions.linux ? tagrel)) (
      upstreamPatch "all/0001-cachyos-base-all.patch"
    )
    ++ schedPatches
    ++ lib.optionals (cachyConfig.cpuSched == "hardened") (
      if version == "7.0.11" && toString (cachyConfig.versions.linux.tagrel or "") == "1" then
        [ ./patches/0001-hardened.patch ]
      else
        upstreamPatch "misc/0001-hardened.patch"
    );

  options = import ./options.nix { inherit lib; };
  inherit (options) buildPkgbuildConfig;

  pkgbuildConfig =
    assert cachyConfig.useLTO == "none" || stdenv.cc.isClang;
    assert
      (cachyConfig.autoFDO && cachyConfig.autoFDOProfile != null)
      || (cachyConfig.propeller && cachyConfig.propellerProfiles != null)
      -> cachyConfig.useLTO != "none";
    buildPkgbuildConfig cachyConfig;

in
stdenv.mkDerivation (finalAttrs: {
  inherit src patches;
  name = "linux-cachyos-config";
  nativeBuildInputs = kernel.nativeBuildInputs ++ kernel.buildInputs;

  makeFlags = commonMakeFlags;

  buildPhase = ''

    runHook preBuild

    cp "${config-src}/${cachyConfig.taste}/config" ".config"
    make $makeFlags olddefconfig
    patchShebangs scripts/config
    scripts/config ${lib.concatStringsSep " " pkgbuildConfig}
    make $makeFlags olddefconfig

    runHook postBuild
  '';

  installPhase = ''

    runHook preInstall

    cp .config $out

    runHook postInstall
  '';

  meta = ogKernelConfigfile.meta // {
    platforms = [ "x86_64-linux" ];
  };

  passthru = {
    inherit
      cachyConfig
      commonMakeFlags
      stdenv
      ;
    kernelPatches = patches;
    extraVerPatch = ''

      sed -Ei"" 's/EXTRAVERSION = ?(.*)$/EXTRAVERSION = \1${cachyConfig.versions.suffix}/g' Makefile
    '';
    # AutoFDO/Propeller: mirrors upstream PKGBUILD — the flag is only passed
    # when the feature is enabled *and* a profile path was supplied. Kernel
    # expects a single file for AutoFDO, and <prefix>_cc_profile.txt /
    # <prefix>_ld_profile.txt for Propeller.
    preparedMakeFlags =
      lib.optionals (cachyConfig.autoFDO && cachyConfig.autoFDOProfile != null) [
        "CLANG_AUTOFDO_PROFILE=${cachyConfig.autoFDOProfile}"
      ]
      ++ lib.optionals (cachyConfig.propeller && cachyConfig.propellerProfiles != null) [
        "CLANG_PROPELLER_PROFILE_PREFIX=${cachyConfig.propellerProfiles}/propeller"
      ];
  };
})
