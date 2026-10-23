{ lib }:
let
  source = import ../../nix/source.nix { inherit lib; } ../..;
in
{
  test-runtime-excluded = {
    expr = builtins.pathExists (source + "/.runtime");
    expected = false;
  };
  test-devenv-state-excluded = {
    expr = builtins.pathExists (source + "/.devenv");
    expected = false;
  };
  test-candidate-included = {
    expr = builtins.pathExists (source + "/tests/qualification/source.nix");
    expected = true;
  };
}
