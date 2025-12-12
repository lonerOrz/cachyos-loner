pkgs:
pkgs.nixfmt-tree.override {
  settings = {
    tree-root-file = ".git/index";
    excludes = [
    ];
    formatter.nixfmt = {
      command = "nixfmt";
      includes = [ "*.nix" ];
    };
  };
}
