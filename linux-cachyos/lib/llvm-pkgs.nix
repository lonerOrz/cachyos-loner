{
  final,
  flakes,
  ...
}:

let
  projectUtils = import ../../utils.nix { lib = final.lib; };
  bumpedFinal = final.extend (finalFinal: _prevFinal: { llvmPackages = finalFinal.llvmPackages_22; });
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

    # NOTE: Don't use the compilers from the cross-compiled pkgsLLVM
    inherit (bumpedFinal)
      llvmPackages
      rustc
      rust-bindgen
      rustPlatform
      ;
  }
)
