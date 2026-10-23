{ fx, lib }:
let
  T = fx.types;
  poison = throw "qualification poison";
  collect =
    type: value:
    let
      result = fx.handle {
        state = {
          events = [ ];
          bounces = 0;
        };
        handlers = {
          deriveBounce =
            { param, state }:
            fx.effects.typecheck.collecting.deriveBounce {
              inherit param;
              state = state // {
                bounces = state.bounces + 1;
              };
            };
          typeCheck = { param, state }: {
            resume = null;
            state = state // {
              events = [
                {
                  path = map (p: p.segment) param.path;
                  inherit (param) reason;
                }
              ]
              ++ state.events;
            };
          };
        };
      } (fx.map fx.state.mkThunk (type.validate value));
    in
    {
      events = lib.reverseList result.state.events;
      inherit (result.state) bounces;
      inherit (result) value;
    };
  events = type: value: (collect type value).events;
  event = path: reason: { inherit path reason; };
  inner = T.Record { x = T.Int; };
  nullable = T.Maybe inner;
  extras = {
    x = 1;
    a = poison;
    z = poison;
  };
  extraEvents = prefix: [
    (event (prefix ++ [ ".a" ]) "extra-field")
    (event (prefix ++ [ ".z" ]) "extra-field")
  ];
  positive = T.refined "Positive" T.Int (n: n > 0);
in
{
  test-null-skips-predicate = {
    expr = events (T.Maybe (T.refined "Throwing" T.Int (_: poison))) null;
    expected = [ ];
  };
  test-valid-value = {
    expr = events nullable { x = 1; };
    expected = [ ];
  };
  test-primitive-failure = {
    expr = events (T.Maybe T.Int) false;
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-root-extras = {
    expr = events nullable extras;
    expected = extraEvents [ ];
  };
  test-record-extras = {
    expr = events (T.Record { nested = nullable; }) { nested = extras; };
    expected = extraEvents [ ".nested" ];
  };
  test-list-extras = {
    expr = events (T.ListOf nullable) [ extras ];
    expected = extraEvents [ "[0]" ];
  };
  test-variant-extras = {
    expr = events (T.Variant { Some = nullable; }) {
      _tag = "Some";
      value = extras;
    };
    expected = extraEvents [ "#Some" ];
  };
  test-nested-refinements = {
    expr =
      events
        (T.Maybe (
          T.Record {
            x = positive;
            y = positive;
          }
        ))
        {
          x = -1;
          y = -2;
        };
    expected = [
      (event [ ".x" ] "predicate-failed")
      (event [ ".y" ] "predicate-failed")
    ];
  };
  test-thrown-input = {
    expr = events nullable poison;
    expectedError = {
      type = "ThrownError";
      msg = "qualification poison";
    };
  };
  test-thrown-predicate = {
    expr = events (T.Maybe (T.refined "Throwing" T.Int (_: poison))) 1;
    expectedError = {
      type = "ThrownError";
      msg = "qualification poison";
    };
  };
  test-opaque-value = {
    expr = builtins.attrNames (
      fx.state.forceThunk (collect (T.Maybe (T.Record { payload = T.Any; })) { payload = poison; }).value
    );
    expected = [ "payload" ];
  };
  test-fuel-exhaustion = {
    expr =
      let
        deep = builtins.foldl' (type: _: T.Maybe type) T.Int (builtins.genList (i: i) 514);
        result = collect deep false;
      in
      {
        inherit (result) events bounces;
      };
    expected = {
      events = [ (event [ ] "shape-mismatch") ];
      bounces = 1;
    };
  };
}
