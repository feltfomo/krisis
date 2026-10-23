{ inputs, pkgs }:
let
  fxSource = pkgs.applyPatches {
    name = "nix-effects-validation";
    src = inputs.nix-effects;
    patches = [ ../patches/nix-effects-validation.patch ];
  };
in
{
  inherit fxSource;
  fx = import fxSource { inherit (pkgs) lib; };
}
