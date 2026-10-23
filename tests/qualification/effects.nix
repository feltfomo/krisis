{ fx, lib }:
let
  inherit (fx.state) mkThunk forceThunk;
  poison = throw "transport poison";
  ask = fx.send "qualification.context" null;
  withContext =
    defaults:
    fx.effects.scope.provide {
      "qualification.context" = { state, ... }: {
        inherit state;
        resume = mkThunk defaults;
      };
    };
  emit = fx.send "qualification.emit";
  run =
    computation:
    let
      result =
        fx.handle
          {
            state = mkThunk [ ];
            handlers = {
              "qualification.emit" =
                { param, state }:
                let
                  previous = forceThunk state;
                in
                builtins.seq previous {
                  state = mkThunk ([ (mkThunk param) ] ++ previous);
                  resume = null;
                };
              "qualification.outer" = { state, ... }: {
                inherit state;
                resume = null;
              };
              "qualification.fail" = { state, ... }: {
                inherit state;
                abort = {
                  _con = "Failure";
                };
              };
            };
          }
          (
            fx.map (value: {
              _con = "Success";
              value = mkThunk value;
            }) computation
          );
    in
    {
      diagnostics = map forceThunk (lib.reverseList (forceThunk result.state));
      outcome = result.value;
    };
  successful = run (fx.pure { payload = poison; });
  collected = run (
    fx.bind (emit {
      code = "test";
      context = poison;
      message = poison;
    }) (_: fx.bind (fx.send "qualification.outer" null) (_: fx.pure { payload = poison; }))
  );
  scoped =
    withContext
      {
        name = "root";
        context = poison;
      }
      (
        fx.bind ask (
          root:
          fx.bind
            (withContext {
              name = "nested";
              context = poison;
            } (fx.bind (fx.send "qualification.outer" null) (_: ask)))
            (
              nested:
              fx.bind ask (
                restored:
                fx.bind
                  (withContext {
                    name = "sibling";
                    context = poison;
                  } ask)
                  (
                    sibling:
                    fx.pure (mkThunk [
                      root
                      nested
                      restored
                      sibling
                    ])
                  )
              )
            )
        )
      );
  rawControl =
    (fx.handle {
      state = null;
      handlers.write = { param, ... }: {
        state = param;
        resume = null;
      };
    } (fx.bind (fx.send "write" { context = poison; }) (_: fx.pure 1))).value;
  protectedControl = fx.handle {
    state = null;
    handlers.write = { param, ... }: {
      state = mkThunk param;
      resume = null;
    };
  } (fx.bind (fx.send "write" { context = poison; }) (_: fx.pure 1));
in
{
  test-resume-false-continues = {
    expr =
      (fx.handle {
        state = null;
        handlers.reject = { state, ... }: {
          inherit state;
          resume = false;
        };
      } (fx.bind (fx.send "reject" null) (_: fx.pure 1))).value;
    expected = 1;
  };
  test-success-opaque = {
    expr = builtins.attrNames (forceThunk successful.outcome.value);
    expected = [ "payload" ];
  };
  test-collected-opaque = {
    expr = {
      codes = map (d: d.code) collected.diagnostics;
      fields = builtins.attrNames (forceThunk collected.outcome.value);
    };
    expected = {
      codes = [ "test" ];
      fields = [ "payload" ];
    };
  };
  test-scopes = {
    expr = map (carrier: (forceThunk carrier).name) (
      forceThunk (forceThunk (run scoped).outcome.value)
    );
    expected = [
      "root"
      "nested"
      "root"
      "sibling"
    ];
  };
  test-abort-skips-continuation = {
    expr = (run (fx.bind (fx.send "qualification.fail" null) (_: poison))).outcome;
    expected = {
      _con = "Failure";
    };
  };
  test-raw-state-poison-control = {
    expr = rawControl;
    expectedError = {
      type = "ThrownError";
      msg = "transport poison";
    };
  };
  test-protected-state = {
    expr = {
      inherit (protectedControl) value;
      fields = builtins.attrNames (forceThunk protectedControl.state);
    };
    expected = {
      value = 1;
      fields = [ "context" ];
    };
  };
  test-warning-completes = {
    expr =
      (run (
        fx.bind (emit {
          severity = "warning";
          context = poison;
        }) (_: fx.pure 1)
      )).outcome._con;
    expected = "Success";
  };
}
