{ lib }:
let
  axiom = import ../axiom { inherit lib; };
  safe = import ./safe-render.nix {
    inherit lib;
    inherit (axiom) identity validation schema;
  };
  diagnostics = import ./diagnostics.nix {
    inherit lib;
    inherit (axiom) validation schema canonical;
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
