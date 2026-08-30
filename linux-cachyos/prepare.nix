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

  # Select scheduler patches based on configured cpuSched.
  schedPatches =
    if cachyConfig.cpuSched == "eevdf" then
      [ ]
    else if cachyConfig.cpuSched == "hardened" then
      [ ]
    else if cachyConfig.cpuSched == "bore" then
      [ "${patches-src}/${majorMinor}/sched/0001-bore-cachy.patch" ]
    else if cachyConfig.cpuSched == "bmq" then
      [ "${patches-src}/${majorMinor}/sched/0001-prjc-cachy.patch" ]
    else if (cachyConfig.cpuSched == "cachyos" || cachyConfig.cpuSched == "sched-ext") then
      lib.optionals (lib.strings.versionOlder majorMinor "6.12") [
        "${patches-src}/${majorMinor}/sched/0001-sched-ext.patch"
      ]
      ++ lib.optionals (cachyConfig.cpuSched == "cachyos" && version != "6.17-rc1") [
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
      [
        "${patches-src}/${majorMinor}/sched/0001-bore-cachy.patch"
        "${patches-src}/${majorMinor}/misc/0001-rt-i915.patch"
      ]
    else if (cachyConfig.cpuSched == "rt") then
      [ "${patches-src}/${majorMinor}/misc/0001-rt-i915.patch" ]
    else
      throw "Unsupported cachyos _cpu_sched=${toString cachyConfig.cpuSched}";

  # Combine base patchset (if not pre-patched in release tarball) with sched and misc patches.
  patches =
    lib.optionals (!(cachyConfig.versions.linux ? tagrel)) [
      "${patches-src}/${majorMinor}/all/0001-cachyos-base-all.patch"
    ]
    ++ schedPatches
    ++ lib.optional (cachyConfig.cpuSched == "hardened") (
      if version == "7.0.11" && toString (cachyConfig.versions.linux.tagrel or "") == "1" then
        ./patches/0001-hardened.patch
      else
        "${patches-src}/${majorMinor}/misc/0001-hardened.patch"
    );

  options = import ./options.nix { inherit lib; };
  inherit (options) buildPkgbuildConfig;

  pkgbuildConfig =
    assert cachyConfig.useLTO == "none" || stdenv.cc.isClang;
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
  };
})
