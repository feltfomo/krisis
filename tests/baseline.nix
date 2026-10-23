{ lib, axiom }:
let
  k = import ../src { inherit lib axiom; };
  poison = throw "baseline poison";
  diagnostic = k.mkDiagnostic {
    severity = "error";
    code = "test/problem";
    message = "something broke";
    primary = {
      label = "sample";
      source = "modules/example.nix";
    };
    secondaryLabels = [
      {
        label = "related";
        message = "also involved";
      }
    ];
    notes = [ "first note" ];
    help = "fix the sample";
    context = poison;
  };
  reporter = k.mkReporter {
    formatHeader = n: "sample: ${toString n} error(s)";
    formatDiagnostic = d: "  - [${d.code}] ${d.message}";
  };
  bad =
    options:
    k.mkDiagnostic (
      {
        severity = "error";
        code = "test";
        message = "bad";
      }
      // options
    );
  error = expr: {
    inherit expr;
    expectedError = {
      type = "ThrownError";
    };
  };
  drv = {
    type = "derivation";
    name = "poison-package";
    drvPath = poison;
    outPath = poison;
  };
  factory = k.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "sample";
    primary.source = "modules/sample.nix";
  };
in
{
  test-diagnostic-envelope = {
    expr = {
      inherit (diagnostic)
        severity
        code
        primary
        secondaryLabels
        notes
        ;
    };
    expected = {
      severity = "error";
      code = "test/problem";
      primary = {
        label = "sample";
        source = "modules/example.nix";
      };
      secondaryLabels = [
        {
          label = "related";
          message = "also involved";
        }
      ];
      notes = [ "first note" ];
    };
  };
  test-bad-severity = error (bad {
    severity = "fatal";
  });
  test-unknown-field = error (bad {
    surprise = true;
  });
  test-bad-notes = error (bad {
    notes = [ 1 ];
  });
  test-bad-help = error (bad {
    help = [ "not a string" ];
  });
  test-factory = {
    expr = factory {
      code = "missing";
      message = "missing value";
      primary.label = "entry";
    };
    expected = {
      severity = "error";
      code = "sample/missing";
      message = "missing value";
      primary = {
        label = "entry";
        source = "modules/sample.nix";
      };
    };
  };
  test-render-one = {
    expr = reporter.renderOne diagnostic;
    expected = "sample: 1 error(s)\n  - [test/problem] something broke";
  };
  test-render-many = {
    expr = reporter.render [
      diagnostic
      diagnostic
    ];
    expected = "sample: 2 error(s)\n  - [test/problem] something broke\n  - [test/problem] something broke";
  };
  test-checked = {
    expr = reporter.checked [ ] 42;
    expected = 42;
  };
  test-checked-error = error (reporter.checked [ diagnostic ] poison);
  test-fail = error (reporter.failOne diagnostic);
  test-plain = {
    expr = k.renderPlain diagnostic;
    expected = "[test/problem] sample: something broke\n    note: first note\n    help: fix the sample";
  };
  test-plain-bare = {
    expr = k.renderPlain (
      k.mkDiagnostic {
        severity = "warning";
        code = "test/plain";
        message = "bare";
      }
    );
    expected = "[test/plain] bare";
  };
  test-collection = {
    expr = map (d: d.code) (
      k.collectDiagnostics [
        [ diagnostic ]
        [ ]
        [ diagnostic ]
      ]
    );
    expected = [
      "test/problem"
      "test/problem"
    ];
  };
  test-optional-false = {
    expr = k.optionalDiagnostic false poison;
    expected = [ ];
  };
  test-optional-true = {
    expr = map (d: d.code) (k.optionalDiagnostic true diagnostic);
    expected = [ "test/problem" ];
  };
  test-context-value = {
    expr = k.withErrorContext "while evaluating sample callback" 42;
    expected = 42;
  };
  test-context-error = {
    expr = k.withErrorContext "while evaluating sample callback" (throw "original callback");
    expectedError = {
      type = "ThrownError";
      msg = "original callback";
    };
  };
  test-truncate-string = {
    expr = k.safeRenderWith { maxStringLength = 4; } "abcdefgh";
    expected = ''"abcd…"'';
  };
  test-truncate-list = {
    expr = k.safeRenderWith { maxListItems = 2; } [
      1
      2
      3
    ];
    expected = "[1,2] (+1 more)";
  };
  test-opaque-attrs = {
    expr = k.safeRender { token = poison; };
    expected = "<unrenderable value>";
  };
  test-poison-list = {
    expr = k.safeRender [
      "visible"
      poison
    ];
    expected = "<unrenderable value>";
  };
  test-derivation-render = {
    expr = k.safeRender drv;
    expected = "<derivation poison-package>";
  };
  test-derivation-shape = {
    expr = k.safeShape drv;
    expected = "<derivation poison-package>";
  };
  test-shallow-shape = {
    expr = k.safeShapeWith { maxAttrs = 2; } {
      a = poison;
      b = poison;
      c = poison;
    };
    expected = "{ a, b, … (+1) }";
  };
  test-label-identity = {
    expr = k.safeIdentity {
      value = poison;
      label = "unit";
      source = "ignored.nix";
      noun = "declaration";
    };
    expected = "declaration 'unit'";
  };
  test-source-identity = {
    expr = k.safeIdentity {
      value = poison;
      source = "modules/example.nix";
      noun = "declaration";
    };
    expected = "declaration at modules/example.nix";
  };
  test-shape-identity = {
    expr = k.safeIdentity {
      value = {
        token = poison;
      };
      noun = "declaration";
    };
    expected = "declaration { token }";
  };
  test-invalid-render-options = error (k.safeRenderWith { maxListItems = -1; } [ ]);
  test-invalid-shape-options = error (k.safeShapeWith { maxAttrs = "many"; } { });
  test-invalid-identity-options = error (
    k.safeIdentity {
      value = { };
      label = 1;
    }
  );
}
