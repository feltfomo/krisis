{ lib }:
let
  safe = import ./safe-render.nix { inherit lib; };
  diagnostics = import ./diagnostics.nix { inherit lib; };
in
{
  inherit (safe)
    safeRender
    safeRenderWith
    safeShape
    safeShapeWith
    safeIdentity
    ;
  inherit (diagnostics)
    allowedSeverities
    qualifyCode
    mkDiagnostic
    mkDiagnosticFactory
    renderDiagnostics
    throwDiagnostics
    mkReporter
    collectDiagnostics
    optionalDiagnostic
    withErrorContext
    ;
}
