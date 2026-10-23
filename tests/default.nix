{
  lib,
  axiom,
  fx,
}:
{
  baseline = import ./baseline.nix { inherit lib axiom; };
  extensions = import ./extensions.nix { inherit lib axiom; };
  qualification = {
    refinements = import ./qualification/refinements.nix { inherit fx lib; };
    source = import ./qualification/source.nix { inherit lib; };
    nullable = import ./qualification/nullable.nix { inherit lib fx; };
    types = import ./qualification/types.nix { inherit lib fx; };
    effects = import ./qualification/effects.nix { inherit lib fx; };
    contracts = import ./qualification/contracts.nix { inherit fx; };
  };
}
