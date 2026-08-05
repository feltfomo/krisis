{ lib }:
let
  krisis = import ../default.nix { inherit lib; };

  throws = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  poisonContext.token = throw "forced diagnostic context";
  poisonSecret.token = throw "forced secret payload";
  poisonDerivation = {
    type = "derivation";
    name = "poison-package";
    drvPath = throw "forced derivation internals";
    outPath = throw "forced derivation internals";
  };
  poisonList = [
    "visible"
    (throw "forced list payload")
  ];

  diagnostic = krisis.mkDiagnostic {
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
    context = poisonContext;
  };

  problem = krisis.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "sample";
    primary.source = "modules/sample.nix";
  };

  reporter = krisis.mkReporter {
    formatHeader = count: "sample: ${toString count} error(s)";
    formatDiagnostic = item: "  - [${item.code}] ${item.message}";
  };

  cases = [
    {
      name = "diagnostic schema validates the shared fields without forcing context";
      pass =
        diagnostic.severity == "error"
        && diagnostic.code == "test/problem"
        && diagnostic.primary.label == "sample"
        && builtins.length diagnostic.secondaryLabels == 1
        && builtins.length diagnostic.notes == 1;
    }
    {
      name = "diagnostic schema rejects unknown severities fields and malformed optional data";
      pass =
        throws (
          krisis.mkDiagnostic {
            severity = "fatal";
            code = "test";
            message = "bad";
          }
        )
        && throws (
          krisis.mkDiagnostic {
            severity = "error";
            code = "test";
            message = "bad";
            surprise = true;
          }
        )
        && throws (
          krisis.mkDiagnostic {
            severity = "error";
            code = "test";
            message = "bad";
            notes = [ 1 ];
          }
        )
        && throws (
          krisis.mkDiagnostic {
            severity = "error";
            code = "test";
            message = "bad";
            help = [ "not a string" ];
          }
        );
    }
    {
      name = "diagnostic factory binds code namespace severity and primary defaults";
      pass =
        problem {
          code = "missing";
          message = "missing value";
          primary.label = "entry";
        } == {
          severity = "error";
          code = "sample/missing";
          message = "missing value";
          primary = {
            label = "entry";
            source = "modules/sample.nix";
          };
        };
    }
    {
      name = "reporter renders singles aggregates and checked values through one policy";
      pass =
        reporter.renderOne diagnostic == "sample: 1 error(s)\n  - [test/problem] something broke"
        &&
          reporter.render [
            diagnostic
            diagnostic
          ] == "sample: 2 error(s)\n  - [test/problem] something broke\n  - [test/problem] something broke"
        && reporter.checked [ ] 42 == 42
        && throws (reporter.checked [ diagnostic ] 42)
        && throws (reporter.failOne diagnostic);
    }
    {
      name = "collection helpers preserve order and conditional absence";
      pass =
        krisis.collectDiagnostics [
          [ diagnostic ]
          [ ]
          [ diagnostic ]
        ] == [
          diagnostic
          diagnostic
        ]
        && krisis.optionalDiagnostic false diagnostic == [ ]
        && krisis.optionalDiagnostic true diagnostic == [ diagnostic ];
    }
    {
      name = "context wrapper preserves values and propagates callback failures";
      pass =
        krisis.withErrorContext "while evaluating sample callback" 42 == 42
        && throws (krisis.withErrorContext "while evaluating sample callback" (throw "boom"));
    }
    {
      name = "bounded rendering truncates strings and lists without traversing attrsets";
      pass =
        krisis.safeRenderWith { maxStringLength = 4; } "abcdefgh" == ''"abcd…"''
        &&
          krisis.safeRenderWith { maxListItems = 2; } [
            1
            2
            3
          ] == "[1,2] (+1 more)"
        && krisis.safeRender poisonSecret == "<unrenderable value>"
        && krisis.safeRender poisonList == "<unrenderable value>";
    }
    {
      name = "safe rendering identifies derivations without forcing their internals";
      pass =
        krisis.safeRender poisonDerivation == "<derivation poison-package>"
        && krisis.safeShape poisonDerivation == "<derivation poison-package>";
    }
    {
      name = "bounded shape and identity expose only shallow names";
      pass =
        krisis.safeShapeWith { maxAttrs = 2; } {
          a = throw "forced a";
          b = throw "forced b";
          c = throw "forced c";
        } == "{ a, b, … (+1) }"
        &&
          krisis.safeIdentity {
            value = poisonSecret;
            label = "unit";
            source = "ignored.nix";
            noun = "declaration";
          } == "declaration 'unit'"
        &&
          krisis.safeIdentity {
            value = poisonSecret;
            source = "modules/example.nix";
            noun = "declaration";
          } == "declaration at modules/example.nix"
        &&
          krisis.safeIdentity {
            value = poisonSecret;
            noun = "declaration";
          } == "declaration { token }";
    }
    {
      name = "render option validation fails closed";
      pass =
        throws (krisis.safeRenderWith { maxListItems = -1; } [ ])
        && throws (krisis.safeShapeWith { maxAttrs = "many"; } { })
        && throws (
          krisis.safeIdentity {
            value = { };
            label = 1;
          }
        );
    }
  ];

  failing = builtins.filter (case: !case.pass) cases;
  ok =
    if failing == [ ] then
      true
    else
      throw "krisis tests FAILED: ${lib.concatMapStringsSep ", " (case: case.name) failing}";
in
{
  inherit cases ok;
}
