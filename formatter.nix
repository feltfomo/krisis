{ lib, ... }:
{
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "docs/*"
  ]
  ++ map (line: lib.removePrefix "/" line + lib.optionalString (lib.hasSuffix "/" line) "**") (
    lib.filter (line: line != "") (lib.splitString "\n" (builtins.readFile ./.gitignore))
  );

  programs.nixfmt.enable = true;
  programs.statix.enable = true;
}
