{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  bundle = k.report.handlers.collecting { };
  diagnosticRun =
    fx.effects.scope.runWith
      (
        bundle
        // {
          return = value: state: {
            report = bundle.return value state;
            observed = state.count;
          };
        }
      )
      (
        fx.bind (fx.send "application.read" null) (
          value:
          fx.bind (k.report.emit {
            code = "observed";
            severity = "info";
            message = "read completed";
          }) (_: fx.pure value)
        )
      );
in
fx.handle {
  state = 0;
  handlers."application.read" = { state, ... }: {
    state = state + 1;
    resume = 42;
  };
} diagnosticRun
