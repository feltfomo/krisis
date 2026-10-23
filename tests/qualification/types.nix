{ fx, lib }:
let
  T = fx.types;
  H = T.hoas;
  poison = throw "discarded payload forced";
  collect =
    computation:
    lib.reverseList
      (fx.handle {
        state = [ ];
        handlers = {
          inherit (fx.effects.typecheck.collecting) deriveBounce;
          typeCheck = { param, state }: {
            resume = null;
            state = [
              {
                path = map (p: p.segment) param.path;
                inherit (param) reason;
              }
            ]
            ++ state;
          };
        };
      } computation).state;
  event = path: reason: { inherit path reason; };
  generated = H.datatype "Checked" [
    (H.con "Valid" [ (H.field "value" (H.thunk H.any)) ])
    (H.con "Invalid" [ ])
  ];
  generatedCheck = value: collect (T.generic.check.deriveCheck generated.T [ ] value);
  q = import ./bridge.nix { inherit fx lib; };
  product = T.Record {
    x = positive;
    y = positive;
  };
  throwingRefinement = base: T.refined "Throwing" base (_: poison);
  positive = T.refined "Positive" T.Int (n: n > 0);
in
{
  test-independent-errors = {
    expr = q.all [
      (q.check q.types.Int false)
      (q.check q.types.String 1)
    ];
    expected = {
      checked = {
        _con = "Invalid";
      };
      events = [
        {
          path = [ ];
          reason = "shape-mismatch";
        }
        {
          path = [ ];
          reason = "shape-mismatch";
        }
      ];
    };
  };
  test-variant-invalid-tag-type = {
    expr = collect (
      (T.Variant { Some = T.Int; }).validate {
        _tag = 1;
        value = poison;
      }
    );
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-either-invalid-tag-type = {
    expr = collect (
      (T.Either T.Int T.String).validate {
        _tag = 1;
        value = poison;
      }
    );
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-generated-valid = {
    expr = generatedCheck {
      _con = "Valid";
      value = fx.state.mkThunk poison;
    };
    expected = [ ];
  };
  test-generated-missing-field = {
    expr = generatedCheck { _con = "Valid"; };
    expected = [ (event [ "#Valid" ".value" ] "missing-field") ];
  };
  test-generated-extra-field = {
    expr = generatedCheck {
      _con = "Valid";
      value = fx.state.mkThunk poison;
      extra = poison;
    };
    expected = [ (event [ "#Valid" ".extra" ] "extra-field") ];
  };
  test-refined-product-child-failures = {
    expr = collect (
      (T.refined "Product" (T.Record {
        x = positive;
        y = positive;
      }) (_: true)).validate
        {
          x = -1;
          y = -2;
        }
    );
    expected = [
      (event [ ".x" ] "predicate-failed")
      (event [ ".y" ] "predicate-failed")
    ];
  };
  test-opaque-root = {
    expr = collect (T.Any.validate poison);
    expected = [ ];
  };
  test-nullable-opaque-field = {
    expr = collect (
      (T.Record { opaque = T.Maybe T.Any; }).validate {
        opaque = {
          token = poison;
        };
      }
    );
    expected = [ ];
  };

  test-other-tag-shapes = {
    expr =
      map
        (
          tag:
          collect (
            (T.Variant { Some = T.Int; }).validate {
              _tag = tag;
              value = poison;
            }
          )
        )
        [
          null
          false
          [ ]
          { }
        ];
    expected = builtins.genList (_: [ (event [ ] "shape-mismatch") ]) 4;
  };
  test-tag-membership = {
    expr =
      map
        (
          tag:
          (T.Variant { Some = T.Int; }).check {
            _tag = tag;
            value = poison;
          }
        )
        [
          1
          null
          false
          [ ]
          { }
        ];
    expected = [
      false
      false
      false
      false
      false
    ];
  };
  test-unknown-tag = {
    expr = collect (
      (T.Variant { Some = T.Int; }).validate {
        _tag = "Other";
        value = poison;
      }
    );
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-missing-tag = {
    expr = collect ((T.Variant { Some = T.Int; }).validate { value = poison; });
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-valid-tag = {
    expr = collect (
      (T.Variant { Some = T.Int; }).validate {
        _tag = "Some";
        value = 1;
      }
    );
    expected = [ ];
  };
  test-throwing-tag = {
    expr = collect (
      (T.Variant { Some = T.Int; }).validate {
        _tag = poison;
        value = poison;
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "discarded payload forced";
    };
  };
  test-unnamed-refined-product = {
    expr = collect (
      (T.refine product (_: true)).validate {
        x = -1;
        y = -2;
      }
    );
    expected = [
      (event [ ".x" ] "predicate-failed")
      (event [ ".y" ] "predicate-failed")
    ];
  };
  test-skip-predicate-shape = {
    expr = collect ((throwingRefinement product).validate false);
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-skip-predicate-children = {
    expr = collect (
      (throwingRefinement product).validate {
        x = -1;
        y = -2;
      }
    );
    expected = [
      (event [ ".x" ] "predicate-failed")
      (event [ ".y" ] "predicate-failed")
    ];
  };
  test-added-predicate-pass = {
    expr = collect (
      (T.refined "Sum" product (x: x.x + x.y > 0)).validate {
        x = 1;
        y = 2;
      }
    );
    expected = [ ];
  };
  test-added-predicate-fail = {
    expr = collect (
      (T.refined "Sum" product (_: false)).validate {
        x = 1;
        y = 2;
      }
    );
    expected = [ (event [ ] "predicate-failed") ];
  };
  test-added-predicate-throw = {
    expr = collect (
      (throwingRefinement product).validate {
        x = 1;
        y = 2;
      }
    );
    expectedError = {
      type = "ThrownError";
    };
  };
  test-refined-inherited-path = {
    expr = collect (
      (T.Maybe (T.Record { nested = T.refined "Sum" product (_: false); })).validate {
        nested = {
          x = 1;
          y = 2;
        };
      }
    );
    expected = [ (event [ ".nested" ] "predicate-failed") ];
  };
  test-kernel-witness = {
    expr = map (x: collect ((T.refined "Positive" T.Int T.positiveInt).validate x)) [
      1
      0
    ];
    expected = [
      [ ]
      [ (event [ ] "predicate-failed") ]
    ];
  };
  test-chained-refinement = {
    expr = collect ((T.refine (T.refined "Positive" T.Int T.positiveInt) (n: n < 5)).validate 7);
    expected = [ (event [ ] "predicate-failed") ];
  };
  test-generated-invalid-constructor = {
    expr = generatedCheck { _con = "Invalid"; };
    expected = [ ];
  };
  test-generated-multiple-extras = {
    expr = generatedCheck {
      _con = "Invalid";
      a = poison;
      z = poison;
    };
    expected = [
      (event [ "#Invalid" ".a" ] "extra-field")
      (event [ "#Invalid" ".z" ] "extra-field")
    ];
  };
  test-generated-mixed = {
    expr = generatedCheck {
      _con = "Valid";
      extra = poison;
    };
    expected = [
      (event [ "#Valid" ".extra" ] "extra-field")
      (event [ "#Valid" ".value" ] "missing-field")
    ];
  };
  test-generated-unknown = {
    expr = generatedCheck {
      _con = "Unknown";
      value = poison;
    };
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-generated-missing-constructor = {
    expr = generatedCheck { value = poison; };
    expected = [ (event [ ] "shape-mismatch") ];
  };
  test-generated-strict = {
    expr =
      (fx.handle
        {
          state = null;
          handlers = fx.effects.typecheck.strict;
        }
        (
          T.generic.check.deriveCheck generated.T [ ] {
            _con = "Invalid";
            extra = poison;
          }
        )
      ).value;
    expectedError = {
      type = "ThrownError";
      msg = "extra-field";
    };
  };
  test-missing-nullable-event = {
    expr = collect ((T.Record { x = T.Maybe T.Int; }).validate { });
    expected = [ (event [ ".x" ] "missing-field") ];
  };
  test-root-extra-order = {
    expr = collect (
      (T.Record { x = T.Int; }).validate {
        a = poison;
        z = poison;
        x = false;
      }
    );
    expected = [
      (event [ ".a" ] "extra-field")
      (event [ ".z" ] "extra-field")
      (event [ ".x" ] "shape-mismatch")
    ];
  };
  test-quoted-list-variant-path = {
    expr =
      (q.check (q.types.Record { "a.b" = q.types.ListOf (q.types.Variant { Some = q.types.Int; }); }) {
        "a.b" = [
          {
            _tag = "Some";
            value = false;
          }
        ];
      }).events;
    expected = [
      {
        path = [
          { field = "a.b"; }
          { index = 0; }
          { variant = "Some"; }
        ];
        reason = "shape-mismatch";
      }
    ];
  };
  test-dependent-skips = {
    expr = (q.andThen (_: throw "dependent ran") (q.check q.types.Int false)).checked;
    expected = {
      _con = "Invalid";
    };
  };
  test-dependent-valid = {
    expr = q.andThen (x: x + 1) (q.check q.types.Int 1);
    expected = 2;
  };
  test-unsupported = {
    expr = q.check T.Int 1;
    expectedError = {
      type = "ThrownError";
      msg = "unsupported type";
    };
  };
  test-checked-opaque = {
    expr = builtins.attrNames (
      fx.state.forceThunk
        (q.check (q.types.Record { payload = q.types.Any; }) { payload = poison; }).checked.value
    );
    expected = [ "payload" ];
  };
  test-primitive-fragment = {
    expr = map (pair: collect (pair.type.validate pair.value)) [
      {
        type = T.String;
        value = "s";
      }
      {
        type = T.Int;
        value = 1;
      }
      {
        type = T.Bool;
        value = true;
      }
      {
        type = T.Float;
        value = 1.5;
      }
      {
        type = T.Attrs;
        value = {
          x = poison;
        };
      }
      {
        type = T.Path;
        value = ./types.nix;
      }
      {
        type = T.Function;
        value = _: poison;
      }
      {
        type = T.Unit;
        value = null;
      }
    ];
    expected = builtins.genList (_: [ ]) 8;
  };
}
