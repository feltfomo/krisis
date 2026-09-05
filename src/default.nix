{ lib, axiom }:
let
  safe = import ./safe-render.nix {
    inherit lib;
    inherit (axiom) identity validation schema;
  };
  diagnostics = import ./diagnostics.nix {
    inherit lib;
    inherit (axiom) validation schema canonical;
  };
  types = import ./types.nix {
    inherit lib;
    inherit (axiom) validation;
    inherit (diagnostics) mkDiagnostic;
  };
  suggestions = import ./suggestions.nix { inherit lib; };
in
{
  inherit (safe)
    safeRender
    safeRenderWith
    safeShape
    safeShapeWith
    safeIdentity
    ;
  inherit (types) validateType renderPath;
  inherit (suggestions) editDistance suggest suggestWith;
  inherit (diagnostics)
    allowedSeverities
    qualifyCode
    mkDiagnostic
    mkDiagnosticFactory
    renderDiagnostics
    throwDiagnostics
    renderPlain
    mkReporter
    summarizeDiagnostics
    collectDiagnostics
    optionalDiagnostic
    withErrorContext
    ;
}
