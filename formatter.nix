{
  projectRootFile = "flake.nix";

  settings.global.excludes = [ "docs/*" ];

  programs.nixfmt.enable = true;
  programs.statix.enable = true;
}
