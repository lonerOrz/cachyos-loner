{
  final,
  prev,
  variant ? "stable",
  linuxPackages ? null,
  ...
}:

let
  inherit (final.lib.trivial) importJSON;
  projectUtils = import ../utils.nix { lib = final.lib; };
  inherit (projectUtils) overrideFull;

  suffix = if variant == "stable" then "" else "-${variant}";
  versions = importJSON (./. + "/version${suffix}.json");

  kernelPatches = map (p: final.fetchurl { inherit (p) name url hash; }) (
    versions.kernelPatches or [ ]
  );

  updater = final.callPackage ./update.nix { inherit variant; };

  cachyosLinuxPackages = linuxPackages;

  # Mirrors the logic in pkgs/linux-cachyos/lib/llvm-module-overlay.nix
  fixNoVideo =
    prevDrv:
    prevDrv.overrideAttrs (prevAttrs: {
      passthru = prevAttrs.passthru // {
        settings = overrideFull (final // final.xorg) prevAttrs.passthru.settings;
        updateScript = updater;
      };
    });
in

if cachyosLinuxPackages ? nvidiaPackages then
  let
    driver = fixNoVideo (
      cachyosLinuxPackages.nvidiaPackages.mkDriver {
        inherit (versions) version;
        sha256_64bit = versions.hash;
        sha256_aarch64 = versions.aarch64Hash;
        openSha256 = versions.openHash;
        settingsSha256 = versions.settingsHash;
        persistencedSha256 = versions.persistencedHash;
        patchesOpen = kernelPatches;
      }
    );

    needsDevRefFix = variant == "lto";

    # Work around leaked kernel.dev references in NVIDIA kernel
    # modules on the CachyOS LTO kernel. These references trip
    # the strict allowedReferences check in nixpkgs.
    nukeDevRefs =
      drv:
      drv.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.removeReferencesTo ];

        postFixup = (old.postFixup or "") + ''
          find $out/lib/modules -name '*.ko*' \
            -exec remove-references-to \
              -t ${cachyosLinuxPackages.kernel.dev} {} \; \
            2>/dev/null || true
        '';
      });
  in
  driver
  // (
    if needsDevRefFix then
      {
        open = if driver.open != null then nukeDevRefs driver.open else null;

        mod = if driver.mod != null then nukeDevRefs driver.mod else null;
      }
    else
      { }
  )
else
  final.runCommand "unsupported-nvidia-cachyos" { } ''
    mkdir -p $out
    echo "nvidia-cachyos is unsupported on ${final.system}" > $out/README
  ''
