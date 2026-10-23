{ lib, render }:
{
  module = report: {
    assertions = [
      {
        assertion = report.outcome._con == "Success";
        message = render.blocking report;
      }
    ];
    warnings = map (event: render.plain (event.d // { severity = event.decision.effectiveSeverity; })) (
      builtins.filter (event: event.decision.visible && event.decision.effectiveSeverity == "warning") (
        lib.zipListsWith (d: decision: { inherit d decision; }) report.diagnostics report.visibility
      )
    );
  };
  withErrorContext =
    message: value:
    if !builtins.isString message then
      throw "krisis: error context must be a string"
    else
      builtins.addErrorContext message value;
}
