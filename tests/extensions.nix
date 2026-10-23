{ lib, axiom }:
let
  k = import ../src { inherit lib axiom; };
  poison = throw "baseline poison";
  t = axiom.types;
  check = k.validateType {
    type = t.record {
      ports = t.listOf t.int;
      payload = t.opaque;
    };
    code = "service/shape";
    label = "server";
    path = [ "config" ];
  };
  result = check {
    ports = [
      false
      "x"
    ];
    payload = poison;
  };
  reporter = k.mkReporter { formatDiagnostic = k.renderPlain; };
  error = expr: {
    inherit expr;
    expectedError = {
      type = "ThrownError";
    };
  };
  summary = k.summarizeDiagnostics [
    {
      code = "a";
      severity = "error";
      message = poison;
      context = poison;
    }
    {
      code = "a";
      severity = "warning";
      message = poison;
      context = poison;
    }
    {
      code = "b";
      severity = "error";
      message = poison;
      context = poison;
    }
  ];
in
{
  test-type-paths = {
    expr = map (d: d.context.validation.path) result.diagnostics;
    expected = [
      [
        "config"
        "ports"
        0
      ]
      [
        "config"
        "ports"
        1
      ]
    ];
  };
  test-type-codes = {
    expr = map (d: d.code) result.diagnostics;
    expected = [
      "service/shape"
      "service/shape"
    ];
  };
  test-type-render = {
    expr = reporter.renderOne (builtins.head result.diagnostics);
    expected = "[service/shape] server: $.config.ports[0]: expected int; got bool";
  };
  test-type-success = {
    expr = axiom.validation.isSuccess (check {
      ports = [ 1 ];
      payload = poison;
    });
    expected = true;
  };
  test-failure-fields = {
    expr = builtins.attrNames result;
    expected = [ "diagnostics" ];
  };
  test-bad-type-code = error (
    k.validateType {
      type = t.opaque;
      code = "";
    } poison
  );
  test-bad-type-label = error (
    k.validateType {
      type = t.opaque;
      code = "x";
      label = 1;
    } poison
  );
  test-bad-type-path = error (
    k.validateType {
      type = t.opaque;
      code = "x";
      path = [ (-1) ];
    } poison
  );
  test-thrown-type-input = {
    expr = k.validateType {
      type = t.int;
      code = "x";
    } poison;
    expectedError = {
      type = "ThrownError";
      msg = "baseline poison";
    };
  };
  test-quoted-path = {
    expr = k.renderPath [
      "field"
      0
      "a.b"
      "if"
    ];
    expected = ''$.field[0]."a.b"."if"'';
  };
  test-root-path = {
    expr = k.renderPath [ ];
    expected = "$";
  };
  test-negative-path = error (k.renderPath [ (-1) ]);
  test-bool-path = error (k.renderPath [ true ]);
  test-lazy-finish = {
    expr = builtins.attrNames (reporter.finish (axiom.validation.success { payload = poison; }));
    expected = [ "payload" ];
  };
  test-failed-finish = error (
    reporter.finish {
      inherit (result) diagnostics;
      value = poison;
    }
  );
  test-summary = {
    expr = summary;
    expected = {
      total = 3;
      bySeverity = {
        error = 2;
        warning = 1;
        info = 0;
      };
      byCode = {
        a = 2;
        b = 1;
      };
      hasErrors = true;
    };
  };
  test-empty-summary = {
    expr = k.summarizeDiagnostics [ ];
    expected = {
      total = 0;
      bySeverity = {
        error = 0;
        warning = 0;
        info = 0;
      };
      byCode = { };
      hasErrors = false;
    };
  };
  test-bad-summary-severity =
    error
      (k.summarizeDiagnostics [
        {
          code = "x";
          severity = "fatal";
          context = poison;
        }
      ]).total;
  test-bad-summary-code =
    error
      (k.summarizeDiagnostics [
        {
          code = "";
          severity = "error";
          message = poison;
        }
      ]).total;
  test-root-render = {
    expr = k.safeRender poison;
    expected = "<unrenderable value>";
  };
  test-root-shape = {
    expr = k.safeShape poison;
    expected = "<unrenderable value>";
  };
  test-custom-fallback = {
    expr = k.safeRenderWith { fallback = "hidden"; } poison;
    expected = "hidden";
  };
  test-function-options = error (k.safeRenderWith { maxListItems = -1; } (_: poison));
  test-function-shape-options = error (k.safeShapeWith { maxAttrs = -1; } (_: poison));
  test-root-options = error (k.safeRenderWith { maxListItems = -1; } poison);
  test-lazy-tail = {
    expr = k.safeRenderWith { maxListItems = 1; } [
      1
      poison
    ];
    expected = "[1] (+1 more)";
  };
  test-zero-prefix = {
    expr = k.safeRenderWith { maxListItems = 0; } [ poison ];
    expected = "[] (+1 more)";
  };
  test-derivation-name = {
    expr = k.safeRender {
      type = "derivation";
      name = poison;
      outPath = poison;
    };
    expected = "<derivation ?>";
  };
  test-suggestions = {
    expr =
      map
        (
          input:
          k.suggest input [
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
    expr = k.suggest "cat" [
      "bat"
      "car"
    ];
    expected = "bat";
  };
  test-suggestion-bound = {
    expr = [
      (k.suggest "abc" [ "def" ])
      (k.suggestWith { maxDistance = 3; } "abc" [ "def" ])
    ];
    expected = [
      null
      "def"
    ];
  };
  test-bad-suggestion-bound = error (k.suggestWith { maxDistance = -1; } "x" [ ]);
  test-bad-suggestion-value = error (k.suggest "x" [ 1 ]);
  test-distance = {
    expr = k.editDistance "kitten" "sitting";
    expected = 3;
  };
}
