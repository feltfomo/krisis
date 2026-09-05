{
  lib,
  validation,
  mkDiagnostic,
}:
let
  renderPath =
    path:
    if !builtins.isList path then
      throw "krisis: validation path must be a list"
    else
      "$"
      + lib.concatMapStrings (
        part:
        if builtins.isString part then
          ".${lib.strings.escapeNixIdentifier part}"
        else if builtins.isInt part && part >= 0 then
          "[${toString part}]"
        else
          throw "krisis: validation path components must be strings or non-negative integers"
      ) path;

  validateType =
    {
      type,
      code,
      label ? null,
      source ? null,
      severity ? "error",
      path ? [ ],
    }:
    let
      template = mkDiagnostic {
        inherit code severity;
        message = "";
        primary =
          lib.optionalAttrs (label != null) { inherit label; }
          // lib.optionalAttrs (source != null) { inherit source; };
      };
      checkedPath = renderPath path;
      adapt =
        problem:
        let
          located = problem // {
            path = path ++ problem.path;
          };
        in
        mkDiagnostic (
          template
          // {
            message = "${renderPath located.path}: expected ${located.expected}; got ${located.actual}";
            context.validation = located;
          }
        );
    in
    value:
    builtins.seq template (
      builtins.seq checkedPath (type.validate value |> validation.mapDiagnostics adapt)
    );
in
{
  inherit renderPath validateType;
}
