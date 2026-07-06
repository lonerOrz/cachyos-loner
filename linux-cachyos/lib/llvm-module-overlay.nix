{
  final,
  ...
}:
kernel: _finalModules: prevModules:

let
  projectUtils = import ../../utils.nix { lib = final.lib; };
  inherit (projectUtils) markBroken overrideFull multiOverride;

  fixNoVideo =
    prevDrv:
    prevDrv.overrideAttrs (prevAttrs: {
      passthru = prevAttrs.passthru // {
        settings = overrideFull (final // final.xorg) prevAttrs.passthru.settings;
      };
    });
in
with prevModules;
{
  cpupower = prevModules.cpupower.override {
    inherit (final) pciutils gettext which;
  };

  evdi =
    multiOverride prevModules.evdi
      {
        inherit (final) python3;
      }
      (prevAttrs: {
        env = prevAttrs.env // {
          CFLAGS = "";
        };
        makeFlags = prevAttrs.makeFlags ++ [
          "CFLAGS=${
            builtins.replaceStrings [ "discarded-qualifiers" ] [ "ignored-qualifiers" ] prevAttrs.env.CFLAGS
          }"
        ];
        postPatch = ''
          substituteInPlace Makefile \
            --replace-fail 'discarded-qualifiers' 'ignored-qualifiers'
        '';
        # Don't build userspace stuff
        postBuild = "";
        installPhase =
          builtins.replaceStrings [ "install -Dm755 library/libevdi.so" ] [ "#" ]
            prevAttrs.installPhase;
      });

  nvidia_x11 = fixNoVideo nvidia_x11;
  nvidia_x11_beta = fixNoVideo nvidia_x11_beta;
  nvidia_x11_latest = fixNoVideo nvidia_x11_latest;
  nvidia_x11_legacy535 = fixNoVideo nvidia_x11_legacy535;
  nvidia_x11_legacy470 = markBroken nvidia_x11_legacy470;
  nvidia_dc = markBroken nvidia_dc;

  nvidiaPackages = nvidiaPackages.extend (
    _finalNV: prevNV: with prevNV; {
      production = fixNoVideo production;
      stable = fixNoVideo stable;
      beta = fixNoVideo beta;
      vulkan_beta = fixNoVideo vulkan_beta;
      latest = fixNoVideo latest;
      legacy_535 = fixNoVideo legacy_535;
      legacy_580 = fixNoVideo legacy_580;
      legacy_470 = markBroken legacy_470;
      dc_590 = markBroken dc_590;
      dc_580 = markBroken dc_580;
      dc_570 = markBroken dc_570;
    }
  );

  # perf needs systemtap fixed first
  perf = markBroken perf;

  ryzen-smu = prevModules.ryzen-smu.overrideAttrs (prevAttrs: {
    makeFlags = (builtins.filter (s: builtins.substring 0 3 s != "CC=") prevAttrs.makeFlags) ++ kernel.commonMakeFlags;
  });

  virtualbox =
    multiOverride virtualbox
      {
        inherit (final) virtualbox;
      }
      (prevAttrs: {
        makeFlags = prevAttrs.makeFlags ++ kernel.commonMakeFlags;
      });

  zenpower = zenpower.overrideAttrs (prevAttrs: {
    makeFlags =
      prevAttrs.makeFlags
      ++ kernel.commonMakeFlags
      ++ [
        "KBUILD_CFLAGS="
      ];
  });
}
