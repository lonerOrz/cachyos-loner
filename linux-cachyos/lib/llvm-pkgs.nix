{
  final,
  flakes,
  ...
}:

let
  projectUtils = import ../../utils.nix { lib = final.lib; };
  # Rust-for-Linux builds rustc against this same LLVM; take it from rustc.
  bumpedFinal = final.extend (
    finalFinal: _prevFinal: { llvmPackages = finalFinal.rustc-unwrapped.llvmPackages; }
  );
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
      rustc-unwrapped
      rust-bindgen-unwrapped
      rustfmt-nightly
      rustPlatform
      ;
  }
)
