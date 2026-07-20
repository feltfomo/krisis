{ lib }:
let
  invalid =
    field: expected: value:
    throw "krisis: diagnostic ${field} must be ${expected}; got ${builtins.typeOf value}";

  validatePrimary =
    primary:
    if !builtins.isAttrs primary then
      invalid "primary" "an attribute set" primary
    else if
      builtins.any (
        name:
        !(builtins.elem name [
          "label"
          "source"
        ])
      ) (builtins.attrNames primary)
    then
      throw "krisis: diagnostic primary accepts only label and source"
    else if primary ? label && !builtins.isString primary.label then
      invalid "primary.label" "a string" primary.label
    else if primary ? source && !builtins.isString primary.source then
      invalid "primary.source" "a string" primary.source
    else
      primary;

  mkDiagnostic =
    args@{
      severity,
      code,
      message,
      primary ? null,
      ...
    }:
    if !builtins.isString severity then
      invalid "severity" "a string" severity
    else if !builtins.isString code then
      invalid "code" "a string" code
    else if !builtins.isString message then
      invalid "message" "a string" message
    else
      {
        inherit severity code message;
      }
      // lib.optionalAttrs (primary != null) { primary = validatePrimary primary; }
      // lib.optionalAttrs (args ? secondaryLabels) { inherit (args) secondaryLabels; }
      // lib.optionalAttrs (args ? notes) { inherit (args) notes; }
      // lib.optionalAttrs (args ? help) { inherit (args) help; }
      // lib.optionalAttrs (args ? context) { inherit (args) context; };

  renderDiagnostics =
    {
      diagnostics,
      formatDiagnostic,
      formatHeader ? (_count: null),
      separator ? "\n",
    }:
    let
      header = formatHeader (builtins.length diagnostics);
      parts = lib.optional (header != null) header ++ map formatDiagnostic diagnostics;
    in
    lib.concatStringsSep separator parts;

  throwDiagnostics = args: throw (renderDiagnostics args);
in
{
  inherit mkDiagnostic renderDiagnostics throwDiagnostics;
}
