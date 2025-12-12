{
  flakes,
  homeManagerModules ? self.homeManagerModules,
  nixpkgs ? flakes.nixpkgs,
  home-manager ? flakes.home-manager,
  packages ? self.legacyPackages,
  self ? flakes.self,
  applyOverlay ? self.utils.applyOverlay,
}:

# The following shells are used to help our maintainers and CI/CDs.
let
  mkShells =
    projectPkgs: nixPkgs:
    let
      pkgs = applyOverlay {
        inherit projectPkgs;
        pkgs = nixPkgs;
        replace = true;
        merge = true;
      };
      inherit (pkgs) callPackage;

      mkShell =
        if nixPkgs.stdenv.isLinux then
          opts:
          pkgs.mkShell (
            opts
            // {
              env = (opts.env or { }) // {
                # as seen on https://nixos.wiki/wiki/Locales
                LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
              };
            }
          )
        else
          pkgs.mkShell;

      recursionHelper = callPackage ./shared/recursion-helper.nix {
        inherit (pkgs.stdenv.hostPlatform) system;
      };

      # Matches build.yml and full-bump.yml
      pinnedNix = pkgs.nixVersions.latest;

      builder = callPackage ./tools/builder {
        nix = pinnedNix;
        inherit dry-build; # dry-build restored
      };
      dry-build = callPackage ./tools/dry-build {
        allPackages = projectPkgs;
        flakeSelf = self;
        inherit recursionHelper;
        inherit (pkgs) projectUtils;
      };

      evaluated = callPackage ./tools/eval {
        allPackages = projectPkgs;
        inherit recursionHelper;
      };

      bumper = callPackage ./tools/bumper {
        allPackages = projectPkgs;
        nix = pinnedNix;
        flakeSelf = self;
        inherit recursionHelper nixpkgs;
      };

    in
    {
      default = mkShell {
        buildInputs = [ builder ];
      };
      dry-build = mkShell {
        env.PROJECT_DRY_BUILD = dry-build;
        shellHook = "echo $PROJECT_DRY_BUILD";
      };

      evaluator = mkShell {
        env.PROJECT_EVALUATED = evaluated;
        shellHook = "echo $PROJECT_EVALUATED";
      };

      updater = mkShell {
        buildInputs = [ bumper ];
      };

    };
in
{
  x86_64-linux = mkShells packages.x86_64-linux nixpkgs.legacyPackages.x86_64-linux;
  aarch64-linux = mkShells packages.aarch64-linux nixpkgs.legacyPackages.aarch64-linux;
  aarch64-darwin = mkShells packages.aarch64-darwin nixpkgs.legacyPackages.aarch64-darwin;
}
