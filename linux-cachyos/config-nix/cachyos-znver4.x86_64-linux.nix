builtins.removeAttrs (import ./cachyos-lto.x86_64-linux.nix) [ "CONFIG_GENERIC_CPU" "CONFIG_X86_64_VERSION" ] // { "CONFIG_MZEN4" = "y"; }
