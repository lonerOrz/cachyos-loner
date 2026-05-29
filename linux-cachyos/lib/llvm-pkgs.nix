{ final, flakes, ... }:

let
  projectUtils = import ../../utils.nix { lib = final.lib; };
in
(final.pkgsLLVM.extend flakes.self.overlays.default).extend (
  _finalLLVM: prevLLVM: {
    inherit (final)
      dbus
      libdrm
      libgbm
      libGL
      libxv
      libtirpc
      wayland
      xorg
      ;
    cups = projectUtils.markBroken prevLLVM.cups;
    doctest = prevLLVM.doctest.overrideAttrs (prevAttrs: {
      postPatch = (prevAttrs.postPatch or "") + ''
        substituteInPlace scripts/cmake/common.cmake \
          --replace-fail '-Wall' '-Wall -Wno-error=thread-safety-negative'
      '';
    });
  }
)
