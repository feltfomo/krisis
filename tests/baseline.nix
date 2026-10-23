{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  poison = throw "core poison";
  err = expr: {
    inherit expr;
    expectedError.type = "ThrownError";
  };
  make =
    extra:
    k.diagnostic.make (
      {
        code = "test";
        message = "problem";
      }
      // extra
    );
  deferred = make {
    message = poison;
    primary = poison;
    related = poison;
    notes = poison;
    help = poison;
    context = poison;
  };
  factory = k.diagnostic.factory {
    namespace = "sample";
    primary.source = "module.nix";
  };
  drv = {
    type = "derivation";
    name = "pkg";
    drvPath = poison;
    outPath = poison;
  };
  inherit (k.report.run { } (k.report.emit deferred)) summary;
  inspectionErrors = lib.genAttrs [ "scalar" "function" "derivation" "list" "attrs" "root" ] (
    branch:
    let
      value =
        {
          scalar = 1;
          function = _: poison;
          derivation = drv;
          list = [ ];
          attrs = { };
          root = poison;
        }
        .${branch};
    in
    {
      test-value-options = err (k.inspect.value { maxListItems = -1; } value);
      test-shape-options = err (k.inspect.shape { maxAttrs = -1; } value);
      test-value-unknown = err (k.inspect.value { unknown = poison; } value);
      test-shape-unknown = err (k.inspect.shape { unknown = poison; } value);
    }
  );
in
{
  inherit inspectionErrors;
  test-envelope-deferred = {
    expr = summary;
    expected = {
      total = 1;
      hasErrors = true;
      bySeverity = {
        error = 1;
        warning = 0;
        info = 0;
      };
      byCode.test = 1;
    };
  };
  test-unknown-field = err (make { surprise = poison; }).code;
  test-invalid-severity = err (make { severity = "fatal"; }).code;
  test-empty-code = err (make { code = ""; }).code;
  test-missing-message = err (k.diagnostic.make { code = "x"; }).code;
  test-bad-message = err (
    k.render.project (make {
      message = 1;
    })
  );
  test-bad-notes = err (
    k.render.project (make {
      notes = [ 1 ];
    })
  );
  test-bad-help = err (
    k.render.project (make {
      help = false;
    })
  );
  test-bad-related = err (
    k.render.project (make {
      related = [
        {
          location.label = "a";
          message = 1;
        }
      ];
    })
  );
  test-related-unknown = err (
    k.render.project (make {
      related = [
        {
          location.label = "a";
          extra = poison;
        }
      ];
    })
  );
  test-project-context = {
    expr = k.render.project (make {
      context = poison;
    });
    expected = {
      severity = "error";
      code = "test";
      message = "problem";
      primary = null;
      related = [ ];
      notes = [ ];
      help = null;
    };
  };
  test-factory = {
    expr =
      (factory {
        code = "missing";
        message = "missing";
        primary.label = "entry";
      }).primary;
    expected = {
      label = "entry";
      source = "module.nix";
      path = [ ];
      range = null;
    };
  };
  test-factory-code = {
    expr =
      (factory {
        code = "missing";
        message = poison;
      }).code;
    expected = "sample/missing";
  };
  test-factory-override = {
    expr =
      (factory {
        code = "x";
        message = "x";
        primary.source = "call.nix";
      }).primary.source;
    expected = "call.nix";
  };
  test-factory-null-clears = {
    expr =
      (factory {
        code = "x";
        message = "x";
        primary = null;
      }).primary;
    expected = null;
  };
  test-factory-unused-default = {
    expr =
      ((k.diagnostic.factory { primary = poison; }) {
        code = "x";
        message = poison;
      }).code;
    expected = "x";
  };
  test-factory-controls = err (
    (k.diagnostic.factory { severity = "fatal"; }) {
      code = "x";
      message = poison;
    }
  );
  test-factory-unknown = err (
    (k.diagnostic.factory { unknown = poison; }) {
      code = "x";
      message = poison;
    }
  );
  test-plain = {
    expr = k.render.plain (make {
      primary.label = "sample";
      notes = [ "note" ];
      help = "fix";
      context = poison;
    });
    expected = "error [test] sample: problem\n    note: note\n    help: fix";
  };
  test-range = {
    expr =
      (make {
        primary = {
          source = "caller";
          range = {
            start = {
              line = 1;
              column = 1;
            };
            end = {
              line = 2;
              column = 1;
            };
          };
        };
      }).primary.range.end.line;
    expected = 2;
  };
  test-range-reversed = err (
    k.render.project (make {
      primary = {
        source = "x";
        range = {
          start = {
            line = 2;
            column = 1;
          };
          end = {
            line = 1;
            column = 2;
          };
        };
      };
    })
  );
  test-range-column-reversed = err (
    k.render.project (make {
      primary = {
        source = "x";
        range = {
          start = {
            line = 1;
            column = 2;
          };
          end = {
            line = 1;
            column = 1;
          };
        };
      };
    })
  );
  test-range-zero = err (
    k.render.project (make {
      primary = {
        source = "x";
        range = {
          start = {
            line = 0;
            column = 1;
          };
          end = {
            line = 1;
            column = 2;
          };
        };
      };
    })
  );
  test-range-source-required = err (
    k.render.project (make {
      primary = {
        label = "x";
        range = {
          start = {
            line = 1;
            column = 1;
          };
          end = {
            line = 1;
            column = 1;
          };
        };
      };
    })
  );
  test-location-empty = err (
    k.render.project (make {
      primary = { };
    })
  );
  test-location-unknown = err (
    k.render.project (make {
      primary = {
        label = "x";
        extra = poison;
      };
    })
  );
  test-path = {
    expr = k.path.render [
      (k.path.field "field")
      (k.path.index 0)
      (k.path.field "a.b")
      (k.path.field "if")
      (k.path.variant "Some")
    ];
    expected = ''$.field[0]."a.b"."if"#"Some"'';
  };
  test-root-path = {
    expr = k.path.render [ ];
    expected = "$";
  };
  test-negative-index = err (k.path.index (-1));
  test-invalid-path = err (k.path.normalize [ true ]);
  test-path-unknown = err (
    k.path.render [
      {
        field = "x";
        extra = 1;
      }
    ]
  );
  test-upstream-path = {
    expr = k.path.normalize [
      {
        upstream = {
          _tag = "Position";
          tag = "SigmaFst";
          segment = "Σ.fst";
          intent = "the first component type of Σ";
        };
      }
    ];
    expected = [
      {
        upstream = {
          _tag = "Position";
          tag = "SigmaFst";
          segment = "Σ.fst";
          intent = "the first component type of Σ";
          rule = null;
          name = null;
          idx = null;
          layer = null;
        };
      }
    ];
  };
  test-context-value = {
    expr = k.nix.withErrorContext "sample context" 42;
    expected = 42;
  };
  test-context-error = {
    expr = k.nix.withErrorContext "sample context" (throw "original callback");
    expectedError = {
      type = "ThrownError";
      msg = "original callback";
    };
  };
  test-context-control = err (k.nix.withErrorContext 1 42);
  test-truncate-string = {
    expr = k.inspect.value { maxStringLength = 4; } "abcdefgh";
    expected = ''"abcd…"'';
  };
  test-truncate-list = {
    expr = k.inspect.value { maxListItems = 2; } [
      1
      2
      poison
    ];
    expected = "[1,2] (+1 more)";
  };
  test-zero-prefix = {
    expr = k.inspect.value { maxListItems = 0; } [ poison ];
    expected = "[] (+1 more)";
  };
  test-opaque-attrs = {
    expr = k.inspect.value { } { token = poison; };
    expected = "<unrenderable value>";
  };
  test-poison-list = {
    expr = k.inspect.value { } [
      "visible"
      poison
    ];
    expected = "<unrenderable value>";
  };
  test-scalars = {
    expr = map (k.inspect.value { }) [
      42
      true
      null
      "x"
    ];
    expected = [
      "42"
      "true"
      "null"
      "\"x\""
    ];
  };
  test-function = {
    expr = k.inspect.value { } (_: poison);
    expected = "<function>";
  };
  test-derivation-shape-name = {
    expr = k.inspect.shape { } (drv // { name = poison; });
    expected = "<derivation ?>";
  };
  test-derivation-missing-name = {
    expr = k.inspect.value { } (removeAttrs drv [ "name" ]);
    expected = "<derivation ?>";
  };
  test-derivation-nonstring-name = {
    expr = k.inspect.value { } (drv // { name = 1; });
    expected = "<derivation ?>";
  };
  test-location-domain = {
    expr =
      k.diagnostic.types.location.check
        (make {
          primary.path = [
            (k.path.field "x")
            (k.path.index 0)
          ];
        }).primary;
    expected = true;
  };
  test-derivation = {
    expr = k.inspect.value { } drv;
    expected = "<derivation pkg>";
  };
  test-derivation-shape = {
    expr = k.inspect.shape { } drv;
    expected = "<derivation pkg>";
  };
  test-derivation-name = {
    expr = k.inspect.value { } (drv // { name = poison; });
    expected = "<derivation ?>";
  };
  test-derivation-type = {
    expr = k.inspect.value { } (drv // { type = poison; });
    expected = "<unrenderable value>";
  };
  test-derivation-type-shape = {
    expr = k.inspect.shape { } {
      type = poison;
      name = poison;
    };
    expected = "{ name, type }";
  };
  test-shallow-shape = {
    expr = k.inspect.shape { maxAttrs = 2; } {
      a = poison;
      b = poison;
      c = poison;
    };
    expected = "{ a, b, … (+1) }";
  };
  test-label = {
    expr = k.inspect.identity {
      value = poison;
      label = "unit";
      source = "ignored";
      noun = "declaration";
    };
    expected = "declaration 'unit'";
  };
  test-source = {
    expr = k.inspect.identity {
      value = poison;
      source = "module.nix";
    };
    expected = "value at module.nix";
  };
  test-shape-identity = {
    expr = k.inspect.identity { value.token = poison; };
    expected = "value { token }";
  };
  test-identity-controls = err (
    k.inspect.identity {
      value = poison;
      label = "x";
      source = 1;
    }
  );
  test-root-value = {
    expr = k.inspect.value { } poison;
    expected = "<unrenderable value>";
  };
  test-root-shape = {
    expr = k.inspect.shape { } poison;
    expected = "<unrenderable value>";
  };
  test-custom-fallback = {
    expr = k.inspect.value { fallback = "hidden"; } poison;
    expected = "hidden";
  };
  test-suggestions = {
    expr =
      map
        (
          input:
          k.suggest.nearest { } input [
            "foo"
            "bar"
            "bat"
            "barrel"
            "fool"
            ""
          ]
        )
        [
          "foo"
          "fou"
          "baz"
          "barrels"
          "unrelated"
          ""
        ];
    expected = [
      "foo"
      "foo"
      "bar"
      "barrel"
      null
      ""
    ];
  };
  test-suggestion-tie = {
    expr = k.suggest.nearest { } "cat" [
      "bat"
      "car"
    ];
    expected = "bat";
  };
  test-suggestion-bound = {
    expr = k.suggest.nearest { maxDistance = 3; } "abc" [ "def" ];
    expected = "def";
  };
  test-suggestion-empty = {
    expr = k.suggest.nearest { } "abc" [ ];
    expected = null;
  };
  test-bad-suggestion-bound = err (k.suggest.nearest { maxDistance = -1; } "x" [ ]);
  test-bad-suggestion-value = err (k.suggest.nearest { } "x" [ 1 ]);
}
