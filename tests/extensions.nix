{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  T = k.validation.types;
  poison = throw "effect poison";
  err = expr: {
    inherit expr;
    expectedError.type = "ThrownError";
  };
  d = code: severity: {
    inherit code severity;
    message = poison;
    primary = poison;
    related = poison;
    help = poison;
    notes = poison;
    context = poison;
  };
  emit = code: severity: k.report.emit (d code severity);
  run = k.report.run { };
  result = run (fx.bind (emit "a" "error") (_: fx.bind (emit "b" "warning") (_: fx.pure poison)));
  check =
    type: value:
    k.validation.check {
      inherit type;
      code = "shape";
    } value;
  checked = computation: fx.state.forceThunk (run computation).outcome.value;
  paths = report: map (item: item.context.validation.path) report.diagnostics;
  located = run (
    check
      (T.Record {
        "a.b" = T.ListOf (T.Variant { Some = T.Int; });
        nullable = T.Maybe T.Int;
      })
      {
        "a.b" = [
          {
            _tag = "Some";
            value = false;
          }
        ];
        extra = poison;
      }
  );
  positive = T.refined "Positive" T.Int (n: n > 0);
  product = T.Record {
    x = positive;
    y = positive;
  };
  large =
    count:
    let
      program = builtins.foldl' (acc: n: fx.bind acc (_: emit (toString n) "warning")) (fx.pure {
        payload = poison;
      }) (builtins.genList (n: n) count);
      r = run program;
    in
    {
      inherit (r.summary) total;
      codes = map (item: item.code) r.diagnostics;
      outcome = r.outcome._con;
    };
  scoped = run (
    k.report.withContext
      {
        namespace = "root";
        primary = poison;
      }
      (
        fx.bind (emit "first" "warning") (
          _:
          fx.bind
            (k.report.withContext {
              namespace = "nested";
              primary = poison;
            } (fx.bind (fx.send "outer" null) (_: emit "second" "warning")))
            (
              _:
              fx.bind (emit "third" "warning") (
                _:
                k.report.withContext {
                  namespace = "sibling";
                  primary = poison;
                } (emit "fourth" "warning")
              )
            )
        )
      )
  );
  scopedOuter =
    k.report.run
      {
        handlers.outer = { state, ... }: {
          inherit state;
          resume = null;
        };
      }
      (
        k.report.withContext
          {
            namespace = "root";
            primary = poison;
          }
          (
            fx.bind (emit "first" "warning") (
              _:
              fx.bind
                (k.report.withContext { namespace = "nested"; } (
                  fx.bind (fx.send "outer" null) (_: emit "second" "warning")
                ))
                (
                  _:
                  fx.bind (emit "third" "warning") (
                    _: k.report.withContext { namespace = "sibling"; } (emit "fourth" "warning")
                  )
                )
            )
          )
      );
  sharedProgram =
    fx.bind
      (k.report.emit {
        code = "first";
        severity = "warning";
        message = "notice";
      })
      (
        _:
        fx.bind (k.report.emit {
          code = "second";
          message = "blocking";
        }) (_: fx.pure { payload = poison; })
      );
  sharedCheck = k.validation.check {
    type = positive;
    code = "shared";
    location = {
      label = "service";
      path = [ { field = "ports"; } ];
    };
  };
  sharedPredicateCheck = k.validation.check {
    type = T.refined "Conditional" T.Int (
      n: if n == 2 then throw "configured predicate exception" else n > 0
    );
    code = "shared-predicate";
  };
  validationProjection = report: {
    outcome = report.outcome._con;
    diagnostics = map (item: k.render.project item // { inherit (item) context; }) report.diagnostics;
  };
  sharedNegative = {
    severity = "error";
    code = "shared";
    message = "$.ports: predicate-failed; expected Positive; got int";
    primary = {
      label = "service";
      source = null;
      range = null;
      path = [ { field = "ports"; } ];
    };
    related = [ ];
    notes = [ ];
    help = null;
    context.validation = {
      path = [ ];
      reason = "predicate-failed";
      expected = "Positive";
      actual = "int";
    };
  };
  sharedWrongShape = sharedNegative // {
    message = "$.ports: shape-mismatch; expected Int; got bool";
    context.validation = {
      path = [ ];
      reason = "shape-mismatch";
      expected = "Int";
      actual = "bool";
    };
  };
  basic = import ../examples/basic.nix { inherit lib fx; };
in
{
  test-order-and-failure = {
    expr = {
      codes = map (item: item.code) result.diagnostics;
      inherit (result) outcome;
    };
    expected = {
      codes = [
        "a"
        "b"
      ];
      outcome._con = "Failure";
    };
  };
  test-warning-success = {
    expr = (run (fx.bind (emit "x" "warning") (_: fx.pure poison))).outcome._con;
    expected = "Success";
  };
  test-return-opaque = {
    expr = builtins.attrNames (fx.state.forceThunk (run (fx.pure { payload = poison; })).outcome.value);
    expected = [ "payload" ];
  };
  test-after-event-opaque = {
    expr = builtins.attrNames (
      fx.state.forceThunk
        (run (fx.bind (emit "x" "warning") (_: fx.pure { payload = poison; }))).outcome.value
    );
    expected = [ "payload" ];
  };
  test-emit-resumes-unit = {
    expr = fx.state.forceThunk (run (emit "x" "warning")).outcome.value;
    expected = null;
  };
  test-explicit-failure = {
    expr = (run (fx.bind (k.report.fail (d "x" "info")) (_: poison))).outcome;
    expected._con = "Failure";
  };
  test-explicit-failure-no-value = {
    expr = builtins.attrNames (run (fx.bind (k.report.fail (d "x" "info")) (_: poison))).outcome;
    expected = [ "_con" ];
  };
  test-policy = {
    expr =
      let
        r = k.report.run {
          policy = {
            warningsAsErrors = true;
            minimumSeverity = "error";
            suppressCodes = [ "x" ];
          };
        } (emit "x" "warning");
      in
      {
        inherit (r) outcome visibility summary;
      };
    expected = {
      outcome._con = "Failure";
      visibility = [
        {
          effectiveSeverity = "error";
          originalSeverity = "warning";
          visible = false;
          suppressed = true;
          belowThreshold = false;
        }
      ];
      summary = {
        total = 1;
        hasErrors = true;
        bySeverity = {
          error = 1;
          warning = 0;
          info = 0;
        };
        byCode.x = 1;
      };
    };
  };
  test-threshold = {
    expr = (k.report.run { policy.minimumSeverity = "error"; } (emit "x" "warning")).visibility;
    expected = [
      {
        effectiveSeverity = "warning";
        originalSeverity = "warning";
        visible = false;
        suppressed = false;
        belowThreshold = true;
      }
    ];
  };
  test-hidden-error = {
    expr = (k.report.run { policy.suppressCodes = [ "x" ]; } (emit "x" "error")).outcome;
    expected._con = "Failure";
  };
  test-empty-policy-control = err (k.report.run { policy.warningsAsErrors = 1; } (fx.pure 1));
  test-policy-unknown = err (k.report.run { policy.unknown = poison; } (fx.pure 1));
  test-same-program-collecting = {
    expr =
      let
        r = run sharedProgram;
      in
      {
        codes = map (item: item.code) r.diagnostics;
        inherit (r) outcome;
      };
    expected = {
      codes = [
        "first"
        "second"
      ];
      outcome._con = "Failure";
    };
  };
  test-same-program-strict = {
    expr = k.report.run { mode = "strict"; } sharedProgram;
    expectedError = {
      type = "ThrownError";
      msg = "error \\[second\\] blocking";
    };
  };
  test-strict-error = {
    expr = k.report.run { mode = "strict"; } (
      fx.bind (k.report.emit {
        code = "strict";
        message = "first";
      }) (_: poison)
    );
    expectedError = {
      type = "ThrownError";
      msg = "error \\[strict\\] first";
    };
  };
  test-strict-warning = {
    expr =
      (k.report.run { mode = "strict"; } (fx.bind (emit "x" "warning") (_: fx.pure 7))).outcome._con;
    expected = "Success";
  };
  test-strict-promoted = err (
    k.report.run
      {
        mode = "strict";
        policy = {
          warningsAsErrors = true;
          suppressCodes = [ "x" ];
        };
      }
      (
        k.report.emit {
          code = "x";
          severity = "warning";
          message = "promoted";
        }
      )
  );
  test-strict-fail-info = err (
    k.report.run { mode = "strict"; } (
      k.report.fail {
        code = "x";
        severity = "info";
        message = "explicit";
      }
    )
  );
  test-collision = err (k.report.run { handlers."krisis.emit" = poison; } (fx.pure 1));
  test-rotating-report-inside-outer-interpreter = {
    expr =
      let
        scopedReport = fx.effects.scope.runWith (k.report.handlers.collecting { }) (
          k.report.withContext
            {
              namespace = "scoped";
              primary = poison;
            }
            (
              fx.bind (fx.send "outer" null) (_: fx.bind (emit "x" "warning") (_: fx.pure { payload = poison; }))
            )
        );
        outer = fx.handle {
          state = 0;
          handlers.outer = { state, ... }: {
            state = state + 1;
            resume = null;
          };
        } scopedReport;
      in
      {
        outerCount = outer.state;
        codes = map (item: item.code) outer.value.diagnostics;
        fields = builtins.attrNames (fx.state.forceThunk outer.value.outcome.value);
      };
    expected = {
      outerCount = 1;
      codes = [ "scoped/x" ];
      fields = [ "payload" ];
    };
  };
  test-outer-state-preserved = {
    expr =
      let
        bundle = k.report.handlers.collecting {
          handlers.outer = { state, ... }: {
            state = state // {
              outerCount = (state.outerCount or 0) + 1;
            };
            resume = null;
          };
        };
        config = bundle // {
          return = value: state: {
            count = state.outerCount;
            report = bundle.return value state;
          };
        };
        r = fx.handle config (
          fx.bind (fx.send "outer" null) (_: fx.bind (emit "x" "warning") (_: fx.send "outer" null))
        );
      in
      {
        inherit (r) count;
        total = r.report.summary.total;
      };
    expected = {
      count = 2;
      total = 1;
    };
  };
  test-checked-invalid-fields = {
    expr =
      let
        bundle = k.report.handlers.collecting { };
        result = fx.handle (bundle // { return = value: _state: value; }) (check T.Int false);
      in
      builtins.attrNames result;
    expected = [ "_con" ];
  };
  test-handler-composition = {
    expr =
      let
        bundle = k.report.handlers.collecting {
          handlers.outer = { state, ... }: {
            inherit state;
            resume = 42;
          };
        };
        r = fx.handle bundle (fx.bind (emit "x" "warning") (_: fx.send "outer" null));
      in
      fx.state.forceThunk r.outcome.value;
    expected = 42;
  };
  test-scope-restoration = {
    expr = map (item: item.code) scopedOuter.diagnostics;
    expected = [
      "root/first"
      "nested/second"
      "root/third"
      "sibling/fourth"
    ];
  };
  test-unhandled-outer = {
    expr = scoped.summary.total;
    expectedError = {
      type = "ThrownError";
      msg = "unhandled effect 'outer'";
    };
  };
  test-scope-unknown = err (run (k.report.withContext { unknown = poison; } (fx.pure 1)));
  test-scope-invalid = err (run (k.report.withContext { namespace = ""; } (fx.pure 1)));
  test-scope-location-defaults = {
    expr =
      let
        r = run (
          k.report.withContext { primary.source = "root"; } (
            k.report.withContext { primary.label = "nested"; } (
              k.report.emit {
                code = "x";
                message = "x";
                primary.label = "call";
              }
            )
          )
        );
      in
      (builtins.head r.diagnostics).primary;
    expected = {
      label = "call";
      source = "root";
      path = [ ];
      range = null;
    };
  };
  test-zero-events = {
    expr = large 0;
    expected = {
      total = 0;
      codes = [ ];
      outcome = "Success";
    };
  };
  test-small-events = {
    expr = large 3;
    expected = {
      total = 3;
      codes = [
        "0"
        "1"
        "2"
      ];
      outcome = "Success";
    };
  };
  test-ten-thousand-events = {
    expr = large 10000;
    expected = {
      total = 10000;
      codes = builtins.genList toString 10000;
      outcome = "Success";
    };
  };
  test-located-failures = {
    expr = paths located;
    expected = [
      [ { field = "extra"; } ]
      [
        { field = "a.b"; }
        { index = 0; }
        { variant = "Some"; }
      ]
      [ { field = "nullable"; } ]
    ];
  };
  test-failure-reasons = {
    expr = map (item: item.context.validation.reason) located.diagnostics;
    expected = [
      "extra-field"
      "shape-mismatch"
      "missing-field"
    ];
  };
  test-failure-no-input = {
    expr = map (item: builtins.attrNames item.context.validation) located.diagnostics;
    expected = builtins.genList (_: [
      "actual"
      "expected"
      "path"
      "reason"
    ]) 3;
  };
  test-valid-value-fields = {
    expr = builtins.attrNames (checked (check T.Int 1));
    expected = [
      "_con"
      "value"
    ];
  };
  test-reused-checker-state-and-diagnostics = {
    expr = map (value: validationProjection (run (sharedCheck value))) [
      (-1)
      1
      false
      2
      (-2)
    ];
    expected = [
      {
        outcome = "Failure";
        diagnostics = [ sharedNegative ];
      }
      {
        outcome = "Success";
        diagnostics = [ ];
      }
      {
        outcome = "Failure";
        diagnostics = [ sharedWrongShape ];
      }
      {
        outcome = "Success";
        diagnostics = [ ];
      }
      {
        outcome = "Failure";
        diagnostics = [ sharedNegative ];
      }
    ];
  };
  test-reused-independent-dependent-suppression = {
    expr = validationProjection (
      run (
        k.validation.andThen (_: poison) (
          k.validation.all (
            map sharedCheck [
              (-1)
              false
              1
            ]
          )
        )
      )
    );
    expected = {
      outcome = "Failure";
      diagnostics = [
        sharedNegative
        sharedWrongShape
      ];
    };
  };
  test-reused-per-value-predicate = {
    expr = map (value: (run (sharedPredicateCheck value)).outcome._con) [
      (-1)
      1
      0
      3
    ];
    expected = [
      "Failure"
      "Success"
      "Failure"
      "Success"
    ];
  };
  test-reused-thrown-input = {
    expr = builtins.seq (run (sharedCheck 1)).outcome._con (run (
      sharedCheck (throw "configured input exception")
    )).summary.total;
    expectedError = {
      type = "ThrownError";
      msg = "configured input exception";
    };
  };
  test-reused-thrown-predicate = {
    expr = builtins.seq (run (sharedPredicateCheck 1)).outcome._con (run (sharedPredicateCheck 2))
    .summary.total;
    expectedError = {
      type = "ThrownError";
      msg = "configured predicate exception";
    };
  };
  test-independent = {
    expr =
      map (item: item.code)
        (run (
          k.validation.all [
            (k.validation.check {
              type = T.Int;
              code = "a";
            } false)
            (k.validation.check {
              type = T.String;
              code = "b";
            } 1)
          ]
        )).diagnostics;
    expected = [
      "a"
      "b"
    ];
  };
  test-dependent-skips = {
    expr = (run (k.validation.andThen (_: poison) (check T.Int false))).outcome;
    expected._con = "Failure";
  };
  test-independent-then-dependent-skips = {
    expr =
      (run (
        k.validation.andThen (_: poison) (
          k.validation.all [
            (check T.Int false)
            (check T.String 1)
          ]
        )
      )).summary.total;
    expected = 2;
  };
  test-dependent-valid = {
    expr =
      fx.state.forceThunk
        (checked (k.validation.andThen (n: check T.Int (n + 1)) (check T.Int 1))).value;
    expected = 2;
  };
  test-all-values = {
    expr =
      fx.state.forceThunk
        (checked (
          k.validation.all [
            (check T.Int 1)
            (check T.String "x")
          ]
        )).value;
    expected = [
      1
      "x"
    ];
  };
  test-all-empty = {
    expr = fx.state.forceThunk (checked (k.validation.all [ ])).value;
    expected = [ ];
  };
  test-opaque-checked = {
    expr = builtins.attrNames (
      fx.state.forceThunk (checked (check (T.Record { payload = T.Any; }) { payload = poison; })).value
    );
    expected = [ "payload" ];
  };
  test-opaque-root = {
    expr = (checked (check T.Any poison))._con;
    expected = "Valid";
  };
  test-unsupported-nullable-child = err (run (check (T.Maybe fx.types.Int) null));
  test-unsupported-empty-list-child = err (run (check (T.ListOf fx.types.Int) [ ]));
  test-unsupported-unselected-branch = err (
    run (
      check
        (T.Variant {
          Good = T.Int;
          Bad = fx.types.String;
        })
        {
          _tag = "Good";
          value = 1;
        }
    )
  );
  test-unsupported = err (run (check fx.types.Int 1));
  test-bad-check-code = err (
    run (
      k.validation.check {
        type = T.Any;
        code = "";
      } poison
    )
  );
  test-bad-check-location = err (
    k.render.project (
      builtins.head
        (run (
          k.validation.check {
            type = T.Int;
            code = "x";
            location.label = 1;
          } false
        )).diagnostics
    )
  );
  test-refinement-paths = {
    expr = paths (
      run (
        check (T.refined "Product" product (_: true)) {
          x = -1;
          y = -2;
        }
      )
    );
    expected = [
      [ { field = "x"; } ]
      [ { field = "y"; } ]
    ];
  };
  test-predicate-skipped = {
    expr =
      (run (
        check (T.refined "Product" product (_: poison)) {
          x = -1;
          y = -2;
        }
      )).summary.total;
    expected = 2;
  };
  test-mixed-refinement = {
    expr =
      (run (check (T.refine (T.refined "OverTen" T.Int (n: n > 10)) fx.types.positiveInt) 5))
      .summary.total;
    expected = 1;
  };
  test-thrown-input = {
    expr = (run (check T.Int poison)).summary.total;
    expectedError = {
      type = "ThrownError";
      msg = "effect poison";
    };
  };
  test-thrown-predicate = {
    expr = (run (check (T.refine T.Int (_: poison)) 1)).summary.total;
    expectedError = {
      type = "ThrownError";
      msg = "effect poison";
    };
  };
  test-null-bypass = {
    expr = (checked (check (T.Maybe (T.refine T.Int (_: poison))) null))._con;
    expected = "Valid";
  };
  test-either = {
    expr = paths (
      run (
        check (T.Either T.Int T.String) {
          _tag = "Right";
          value = false;
        }
      )
    );
    expected = [ [ { variant = "Right"; } ] ];
  };
  test-generated-contracts = {
    expr =
      map
        (
          spec:
          map (con: {
            inherit (con) name;
            fields = map (field: field.name) con.fields;
          }) (fx.types.generic.datatype.datatypeInfo spec.T).constructors
        )
        [
          k.diagnostic.types.checked
          k.diagnostic.types.outcome
        ];
    expected = [
      [
        {
          name = "Valid";
          fields = [ "value" ];
        }
        {
          name = "Invalid";
          fields = [ ];
        }
      ]
      [
        {
          name = "Success";
          fields = [ "value" ];
        }
        {
          name = "Failure";
          fields = [ ];
        }
      ]
    ];
  };
  test-basic-example = {
    expr = {
      inherit (basic.summary) total;
      outcome = basic.outcome._con;
      codes = map (item: item.code) basic.diagnostics;
    };
    expected = {
      total = 1;
      outcome = "Failure";
      codes = [ "service/shape" ];
    };
  };
}
