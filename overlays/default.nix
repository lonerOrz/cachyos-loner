# Conventions:
# - Sort packages in alphabetic order.
# - If the recipe uses `override` or `overrideAttrs`, then use callOverride,
#   otherwise use `final`.
# - Composed names are separated with minus: `lan-mouse`
# - Versions/patches are suffixed with an underline: `mesa_git`, `libei_0_5`, `linux_hdr`

# NOTE:
# - `*_next` packages will be removed once merged into nixpkgs-unstable.

{
  flakes,
  nixpkgs ? flakes.nixpkgs,
  self ? flakes.self,
  selfOverlay ? self.overlays.default,
}:
final: prev:

let
  # Required to load version files.
  inherit (final.lib.trivial) importJSON;

  # Our utilities/helpers.
  projectUtils = import ../shared/utils.nix {
    inherit (final) lib;
    projectOverlay = selfOverlay;
  };
  inherit (projectUtils) multiOverride overrideDescription drvDropUpdateScript;

  # Helps when calling .nix that will override packages.
  callOverride =
    path: attrs:
    import path (
      {
        inherit
          final
          flakes
          projectUtils
          prev
          ;
      }
      // attrs
    );
  # Too much variations
  cachyosPackages = callOverride ../pkgs/linux-cachyos { };

  # Required for kernel packages
  inherit (final.stdenv) isLinux isx86_64;

in
{
  inherit projectUtils;

  linux_cachyos = drvDropUpdateScript cachyosPackages.cachyos-gcc.kernel;
  linux_cachyos-lto = drvDropUpdateScript cachyosPackages.cachyos-lto.kernel;

  linux_cachyos-gcc = drvDropUpdateScript cachyosPackages.cachyos-gcc.kernel;
  linux_cachyos-server = drvDropUpdateScript cachyosPackages.cachyos-server.kernel;
  linux_cachyos-hardened = drvDropUpdateScript cachyosPackages.cachyos-hardened.kernel;
  linux_cachyos-rc = cachyosPackages.cachyos-rc.kernel;
  linux_cachyos-lts = cachyosPackages.cachyos-lts.kernel;

  linuxPackages_cachyos = cachyosPackages.cachyos-gcc;
  linuxPackages_cachyos-lto = cachyosPackages.cachyos-lto;

  linuxPackages_cachyos-gcc = cachyosPackages.cachyos-gcc;
  linuxPackages_cachyos-server = cachyosPackages.cachyos-server;
  linuxPackages_cachyos-hardened = cachyosPackages.cachyos-hardened;
  linuxPackages_cachyos-rc = cachyosPackages.cachyos-rc;
  linuxPackages_cachyos-lts = cachyosPackages.cachyos-lts;

  # zfs_cachyos = cachyosPackages.zfs;
}
