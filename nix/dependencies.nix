{ inputs, pkgs }:
let
  fxSource = import ./qualified-source.nix;
in
{
  inherit fxSource;
  fx = import fxSource { inherit (pkgs) lib; };
  qualifiedPackage = import ./verify-qualified-source.nix { inherit inputs pkgs; };
}
