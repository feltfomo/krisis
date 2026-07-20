{ lib }:
let
  safe = import ./safe-render.nix { inherit lib; };
  diagnostics = import ./diagnostics.nix { inherit lib; };
in
{
  inherit (safe) safeRender safeShape;
  inherit (diagnostics) mkDiagnostic renderDiagnostics throwDiagnostics;
}
