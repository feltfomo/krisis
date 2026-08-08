{ lib }:
let
  axiom = import ../axiom { inherit lib; };
  safe = import ./safe-render.nix {
    inherit lib;
    inherit (axiom) identity;
  };
  diagnostics = import ./diagnostics.nix {
    inherit lib;
    inherit (axiom) validation;
  };
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
    renderPlain
    mkReporter
    collectDiagnostics
    optionalDiagnostic
    withErrorContext
    ;
}
