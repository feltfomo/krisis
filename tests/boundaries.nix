{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  T = k.validation.types;
  poison = throw "unused location or position payload";
  checkAt =
    location: value:
    k.validation.check {
      type = T.Int;
      code = "boundary";
      inherit location;
    } value;
  run = k.report.run { };
  failureAt = location: run (checkAt location false);
  projectAt = location: k.render.project (builtins.head (failureAt location).diagnostics);
  error = expr: {
    inherit expr;
    expectedError.type = "ThrownError";
  };
  upstream = {
    _tag = "Position";
    tag = "SigmaFst";
    segment = "Σ.fst";
    intent = "the first component type of Σ";
    rule = null;
  };
  normalized = upstream // {
    name = null;
    idx = null;
    layer = null;
  };
  normalizePosition = p: k.path.normalize [ { upstream = p; } ];
  presentPosition =
    p:
    k.render.project (
      k.diagnostic.make {
        code = "path";
        message = "located";
        primary.path = [ { upstream = p; } ];
        context = poison;
      }
    );
  invalidPositions = {
    empty = { };
    missing-tag = removeAttrs upstream [ "tag" ];
    wrong-marker = upstream // {
      _tag = "Other";
    };
    empty-tag = upstream // {
      tag = "";
    };
    function-intent = upstream // {
      intent = _: poison;
    };
    nested-intent = upstream // {
      intent = {
        payload = poison;
      };
    };
    malformed-rule = upstream // {
      rule = [ "rule" ];
    };
    malformed-index = upstream // {
      tag = "Tuple";
      idx = -1;
    };
    missing-index = upstream // {
      tag = "Tuple";
    };
    nested-name = upstream // {
      tag = "Case";
      name = {
        payload = poison;
      };
    };
  };
  invalidTests = builtins.mapAttrs (_: p: {
    test-normalize = {
      expr = normalizePosition p;
      expectedError = {
        type = "ThrownError";
        msg = "invalid upstream position";
      };
    };
    test-presentation = {
      expr = presentPosition p;
      expectedError = {
        type = "ThrownError";
        msg = "invalid upstream position";
      };
    };
  }) invalidPositions;
  values =
    count:
    let
      computation = k.validation.all (
        builtins.genList (
          index:
          k.validation.check
            {
              type = T.Any;
              code = "value";
            }
            {
              inherit index;
              payload = poison;
            }
        ) count
      );
      checked = fx.state.forceThunk (run computation).outcome.value;
      result = fx.state.forceThunk checked.value;
    in
    {
      length = builtins.length result;
      indexes = map (v: v.index) result;
    };
in
{
  inherit invalidTests;
  test-valid-throwing-location = {
    expr = (run (checkAt poison 1)).outcome._con;
    expected = "Success";
  };
  test-valid-throwing-location-fields = {
    expr =
      (run (
        checkAt {
          label = poison;
          source = poison;
          path = poison;
          range = poison;
        } 1
      )).outcome._con;
    expected = "Success";
  };
  test-valid-throwing-range-coordinates = {
    expr =
      (run (
        checkAt {
          source = "caller";
          range = {
            start = poison;
            end = poison;
          };
        } 1
      )).outcome._con;
    expected = "Success";
  };
  test-valid-malformed-location = {
    expr = (run (checkAt { label = 1; } 1)).outcome._con;
    expected = "Success";
  };
  test-failure-throwing-location-summary = {
    expr = (failureAt poison).summary;
    expected = {
      total = 1;
      hasErrors = true;
      bySeverity = {
        error = 1;
        warning = 0;
        info = 0;
      };
      byCode.boundary = 1;
    };
  };
  test-failure-location-fields-summary = {
    expr =
      let
        r = failureAt {
          label = poison;
          source = poison;
          range = poison;
          path = poison;
        };
      in
      {
        inherit (builtins.head r.diagnostics) code;
        inherit (r.summary) total;
        outcome = r.outcome._con;
      };
    expected = {
      code = "boundary";
      total = 1;
      outcome = "Failure";
    };
  };
  test-failure-malformed-location-summary = {
    expr = (failureAt { label = 1; }).summary.total;
    expected = 1;
  };
  test-requested-malformed-location = error (projectAt {
    label = 1;
  });
  test-requested-malformed-range = error (projectAt {
    source = "caller";
    range = {
      start = {
        line = 2;
        column = 1;
      };
      end = {
        line = 1;
        column = 1;
      };
    };
  });
  test-requested-unknown-location = error (projectAt {
    label = "x";
    extra = poison;
  });
  test-requested-throwing-location = {
    expr = projectAt poison;
    expectedError = {
      type = "ThrownError";
      msg = "unused location or position payload";
    };
  };
  test-unknown-check-control = {
    expr = run (
      k.validation.check {
        type = T.Any;
        code = "x";
        unexpected = poison;
      } poison
    );
    expectedError.type = "TypeError";
  };
  test-malformed-code-with-unused-location = error (
    run (
      k.validation.check {
        type = T.Any;
        code = "";
        location = poison;
      } poison
    )
  );
  test-malformed-type-with-unused-location = error (
    run (
      k.validation.check {
        type = fx.types.Int;
        code = "x";
        location = poison;
      } 1
    )
  );
  test-position-normalize = {
    expr = normalizePosition upstream;
    expected = [ { upstream = normalized; } ];
  };
  test-position-unknown-tag = {
    expr = normalizePosition (
      upstream
      // {
        tag = "FuturePosition";
        rule = "caller-rule";
      }
    );
    expected = [
      {
        upstream = normalized // {
          tag = "FuturePosition";
          rule = "caller-rule";
        };
      }
    ];
  };
  test-position-parameter = {
    expr = normalizePosition (
      upstream
      // {
        tag = "Tuple";
        idx = 3;
      }
    );
    expected = [
      {
        upstream = normalized // {
          tag = "Tuple";
          idx = 3;
        };
      }
    ];
  };
  test-position-presentation = {
    expr = (presentPosition upstream).primary.path;
    expected = [ { upstream = normalized; } ];
  };
  test-position-presentation-unknown-tag = {
    expr = (presentPosition (upstream // { tag = "FuturePosition"; })).primary.path;
    expected = [
      {
        upstream = normalized // {
          tag = "FuturePosition";
        };
      }
    ];
  };
  test-position-parameter-kinds = {
    expr = map normalizePosition [
      (
        upstream
        // {
          tag = "Case";
          name = "constructor";
        }
      )
      (
        upstream
        // {
          tag = "DConLayer";
          layer = 2;
        }
      )
    ];
    expected = [
      [
        {
          upstream = normalized // {
            tag = "Case";
            name = "constructor";
          };
        }
      ]
      [
        {
          upstream = normalized // {
            tag = "DConLayer";
            layer = 2;
          };
        }
      ]
    ];
  };
  test-position-render = {
    expr = k.path.render [ { inherit upstream; } ];
    expected = ''$<{"_tag":"Position","idx":null,"intent":"the first component type of Σ","layer":null,"name":null,"rule":null,"segment":"Σ.fst","tag":"SigmaFst"}>'';
  };
  test-position-unknown-before-values = {
    expr = normalizePosition (
      upstream
      // {
        extra = poison;
        intent = poison;
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "unknown upstream position field";
    };
  };
  test-position-presentation-unknown-before-values = {
    expr = presentPosition (
      upstream
      // {
        extra = poison;
        intent = poison;
      }
    );
    expectedError = {
      type = "ThrownError";
      msg = "unknown upstream position field";
    };
  };
  test-values-empty = {
    expr = values 0;
    expected = {
      length = 0;
      indexes = [ ];
    };
  };
  test-values-small = {
    expr = values 3;
    expected = {
      length = 3;
      indexes = [
        0
        1
        2
      ];
    };
  };
  test-values-ten-thousand = {
    expr = values 10000;
    expected = {
      length = 10000;
      indexes = builtins.genList (i: i) 10000;
    };
  };
}
