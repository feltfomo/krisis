{ fx, lib }:
let
  q = import ./bridge.nix { inherit fx lib; };
  T = q.types;
  failure = [
    {
      path = [ ];
      reason = "predicate-failed";
    }
  ];
  factories = {
    named =
      label: base: predicate:
      T.refined label base predicate;
    unnamed =
      _label: base: predicate:
      T.refine base predicate;
  };
  cases =
    factory:
    let
      raw = factory "OverTen" T.Int (n: n > 10);
      mixed = factory "PositiveOverTen" raw fx.types.positiveInt;
      reverse = factory "UnderThirty" (factory "Positive" T.Int fx.types.positiveInt) (n: n < 30);
      successive = factory "Bounded" (factory "Upper" mixed (n: n < 30)) (fx.types.inRangeInt 1 100);
      dependent = factory "Dependent" mixed (_: throw "dependent predicate ran");
      compound = T.Record { nested = T.Maybe (T.ListOf successive); };
    in
    {
      test-raw-then-kernel-membership = {
        expr = map mixed.type.check [
          5
          20
        ];
        expected = [
          false
          true
        ];
      };
      test-raw-then-kernel-validation = {
        expr = (q.check mixed 5).events;
        expected = failure;
      };
      test-dependent-predicate-skipped = {
        expr = q.check dependent 5;
        expected = {
          events = failure;
          checked = {
            _con = "Invalid";
          };
        };
      };
      test-dependent-function-skipped = {
        expr = q.andThen (_: throw "dependent function ran") (q.check mixed 5);
        expected = {
          events = failure;
          checked = {
            _con = "Invalid";
          };
        };
      };
      test-accepted-dependent-predicate-throws = {
        expr = q.check dependent 20;
        expectedError = {
          type = "ThrownError";
          msg = "dependent predicate ran";
        };
      };
      test-kernel-then-raw = {
        expr = map reverse.type.check [
          (-1)
          20
          40
        ];
        expected = [
          false
          true
          false
        ];
      };
      test-successive-membership = {
        expr = map successive.type.check [
          5
          20
          40
        ];
        expected = [
          false
          true
          false
        ];
      };
      test-successive-validation = {
        expr = map (value: (q.check successive value).events) [
          5
          20
          40
        ];
        expected = [
          failure
          [ ]
          failure
        ];
      };
      test-compound-located-failures = {
        expr =
          (q.check compound {
            nested = [
              5
              40
            ];
          }).events;
        expected = [
          {
            path = [
              { field = "nested"; }
              { index = 0; }
            ];
            reason = "predicate-failed";
          }
          {
            path = [
              { field = "nested"; }
              { index = 1; }
            ];
            reason = "predicate-failed";
          }
        ];
      };
      test-compound-skips-predicate = {
        expr =
          (q.check (factory "Compound" compound (_: throw "compound predicate ran")) { nested = [ 5 ]; })
          .checked;
        expected = {
          _con = "Invalid";
        };
      };
      test-throwing-raw-predicate = {
        expr = q.check (factory "Mixed" (factory "Throwing" T.Int (
          _: throw "raw predicate ran"
        )) fx.types.positiveInt) 20;
        expectedError = {
          type = "ThrownError";
          msg = "raw predicate ran";
        };
      };
    };
in
(builtins.mapAttrs (_: cases) factories)
// {
  test-admitted-either = {
    expr =
      (q.check (T.Either T.Int T.String) {
        _tag = "Right";
        value = false;
      }).events;
    expected = [
      {
        path = [ { variant = "Right"; } ];
        reason = "shape-mismatch";
      }
    ];
  };
  test-admitted-unnamed-refine = {
    expr = (q.check (T.refine T.Int (n: n > 0)) (-1)).checked;
    expected = {
      _con = "Invalid";
    };
  };
  test-admitted-null = {
    expr = (q.check T.Null null).checked._con;
    expected = "Valid";
  };
}
