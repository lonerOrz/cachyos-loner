{
  final,
  flakes,
  ...
}:

let
  projectUtils = import ../../utils.nix { lib = final.lib; };
  # Pin modern LLVM toolchain for kernel Thin-LTO and Rust for Linux.
  bumpedFinal = final.extend (finalFinal: _prevFinal: { llvmPackages = finalFinal.llvmPackages_22; });
in
(final.pkgsLLVM.extend flakes.self.overlays.default).extend (
  _finalLLVM: prevLLVM: {
    # Re-use host libraries to prevent rebuilding entire userland under pkgsLLVM.
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

    # Inject native compiler toolchain from host rather than cross-compiled target LLVM.
    inherit (bumpedFinal)
      llvmPackages
      rustc
      rust-bindgen
      rustPlatform
      ;
  }
)
