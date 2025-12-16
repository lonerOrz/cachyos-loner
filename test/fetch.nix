# Step 1: Fetch linux-cachyos PKGBUILD + patch repository (test-only)
#
# Responsibilities:
# - Fetch CachyOS/linux-cachyos repository (PKGBUILD)
# - Fetch CachyOS/kernel-patches repository (patch files)
# - Expose both as outputs

{ stdenvNoCC, fetchFromGitHub }:

let
  linuxCachyosPkgbuild = fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux-cachyos";
    rev = "3c3ffceb2ab21e7a67a0565ae636d1471893e35b";
    hash = "sha256-HQRBJcnUvoSh5ZvYWB3/vhvozuXAiOr36BUghEoGK+E=";
  };

  kernelPatches = fetchFromGitHub {
    owner = "CachyOS";
    repo = "kernel-patches";
    rev = "96d3efd823827b734074c0828c695d0c60d8a7d7";
    hash = "sha256-vtNHrRo6f4pk+9XUobPeL3t2RXtm6Dj9z+ngNGK6jN4=";
  };

in
stdenvNoCC.mkDerivation {
  name = "linux-cachyos-fetch";

  nativeBuildInputs = [ ];

  src = linuxCachyosPkgbuild;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/linux-cachyos
    cp -r ${linuxCachyosPkgbuild}/* $out/linux-cachyos/

    mkdir -p $out/kernel-patches
    cp -r ${kernelPatches}/* $out/kernel-patches/
  '';

  passthru = {
    linuxCachyosPkgbuild = "$out/linux-cachyos";
    kernelPatches = "$out/kernel-patches";
  };
}
