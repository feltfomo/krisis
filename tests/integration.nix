{
  lib,
  fx,
  assertionsModule,
}:
let
  k = import ../src { inherit lib fx; };
  poison = throw "module presentation poison";
  run = policy: operation: k.report.run { inherit policy; } operation;
  diagnostic = severity: {
    code = "module";
    inherit severity;
    message = "retained explanation";
    context = poison;
  };
  evaluate =
    report:
    lib.evalModules {
      modules = [
        assertionsModule
        (k.nix.module report)
        {
          options.unrelated = lib.mkOption { type = lib.types.unspecified; };
          config.unrelated = poison;
        }
      ];
    };
  consume =
    report:
    let
      c = (evaluate report).config;
    in
    lib.asserts.checkAssertWarn c.assertions c.warnings "accepted";
  failure = report: {
    expr = consume report;
    expectedError = {
      type = "ThrownError";
      msg = "retained explanation";
    };
  };
  warning = run { } (k.report.emit (diagnostic "warning"));
in
{
  test-warning-consumed = {
    expr = consume warning;
    expected = "accepted";
  };
  test-warning-text = {
    expr = (evaluate warning).config.warnings;
    expected = [ "warning [module] retained explanation" ];
  };
  test-error-consumed = failure (run { } (k.report.emit (diagnostic "error")));
  test-promoted-consumed = failure (
    run { warningsAsErrors = true; } (k.report.emit (diagnostic "warning"))
  );
  test-suppressed-error-consumed = failure (
    run { suppressCodes = [ "module" ]; } (k.report.emit (diagnostic "error"))
  );
  test-info-failure-consumed = failure (
    run { minimumSeverity = "error"; } (k.report.fail (diagnostic "info"))
  );
  test-info-failure-zero-errors = {
    expr = (run { } (k.report.fail (diagnostic "info"))).summary.hasErrors;
    expected = false;
  };
  test-info-does-not-warn = {
    expr = (evaluate (run { } (k.report.emit (diagnostic "info")))).config.warnings;
    expected = [ ];
  };
  test-hidden-warning = {
    expr =
      (evaluate (run { minimumSeverity = "error"; } (k.report.emit (diagnostic "warning"))))
      .config.warnings;
    expected = [ ];
  };
  test-suppressed-warning = {
    expr =
      (evaluate (run { suppressCodes = [ "module" ]; } (k.report.emit (diagnostic "warning"))))
      .config.warnings;
    expected = [ ];
  };
  test-opaque-success = {
    expr = consume (run { } (fx.pure poison));
    expected = "accepted";
  };
  test-assertion-condition-lazy-message = {
    expr =
      map (a: a.assertion)
        (evaluate (run { } (k.report.emit ((diagnostic "error") // { message = poison; }))))
        .config.assertions;
    expected = [ false ];
  };
  test-hidden-message-demanded-on-failure = {
    expr = consume (
      run { suppressCodes = [ "module" ]; } (
        k.report.emit ((diagnostic "error") // { message = poison; })
      )
    );
    expectedError = {
      type = "ThrownError";
      msg = "module presentation poison";
    };
  };
}
