{
  lib,
  axiom,
  krisis,
}:
let
  t = axiom.types;
  v = axiom.validation;
  poison = throw "unreachable diagnostic payload";
  throws = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  type = t.record {
    ports = t.listOf t.int;
    payload = t.opaque;
  };
  check = krisis.validateType {
    inherit type;
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
  reporter = krisis.mkReporter { formatDiagnostic = krisis.renderPlain; };
  summary = krisis.summarizeDiagnostics [
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
  candidates = [
    "foo"
    "bar"
    "bat"
    "barrel"
    "fool"
    ""
  ];
  oldSuggest =
    input: names:
    let
      ranked = builtins.sort (a: b: a.distance < b.distance) (
        map (name: {
          inherit name;
          distance = lib.strings.levenshtein input name;
        }) names
      );
      limit = if builtins.stringLength input <= 4 then 1 else 3;
    in
    if ranked == [ ] || (builtins.head ranked).distance > limit then
      null
    else
      (builtins.head ranked).name;
  evidence = {
    type-bridge-paths =
      map (d: d.context.validation.path) result.diagnostics == [
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
    type-bridge-codes =
      map (d: d.code) result.diagnostics == [
        "service/shape"
        "service/shape"
      ];
    type-bridge-render =
      reporter.renderOne (builtins.head result.diagnostics)
      == "[service/shape] server: $.config.ports[0]: expected int; got bool";
    type-bridge-lazy-success = v.isSuccess (check {
      ports = [ 1 ];
      payload = poison;
    });
    type-bridge-failed-value-absent = !(result ? value);
    type-bridge-validates-options =
      throws (
        krisis.validateType {
          type = t.opaque;
          code = "";
        } poison
      )
      && throws (
        krisis.validateType {
          type = t.opaque;
          code = "x";
          label = 1;
        } poison
      )
      && throws (
        krisis.validateType {
          type = t.opaque;
          code = "x";
          path = [ (-1) ];
        } poison
      );
    type-bridge-root-poison-propagates = throws (
      krisis.validateType {
        type = t.int;
        code = "x";
      } poison
    );
    paths-quote-fields =
      krisis.renderPath [
        "field"
        0
        "a.b"
        "if"
      ] == ''$.field[0]."a.b"."if"'';
    path-root = krisis.renderPath [ ] == "$";
    path-errors = throws (krisis.renderPath [ (-1) ]) && throws (krisis.renderPath [ true ]);
    finish-success-lazy =
      builtins.attrNames (reporter.finish (v.success { payload = poison; })) == [ "payload" ];
    finish-failure-skips-value = throws (
      reporter.finish {
        inherit (result) diagnostics;
        value = poison;
      }
    );
    summary-counts =
      summary == {
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
    empty-summary =
      krisis.summarizeDiagnostics [ ] == {
        total = 0;
        bySeverity = {
          error = 0;
          warning = 0;
          info = 0;
        };
        byCode = { };
        hasErrors = false;
      };
    invalid-summary = throws (
      krisis.summarizeDiagnostics [
        {
          code = "x";
          severity = "fatal";
        }
      ]
    );
    summary-total-validates-envelope =
      let
        invalidCode = krisis.summarizeDiagnostics [
          {
            code = "";
            severity = "error";
            message = poison;
          }
        ];
        invalidSeverity = krisis.summarizeDiagnostics [
          {
            code = "x";
            severity = "fatal";
            context = poison;
          }
        ];
      in
      throws invalidCode.total && throws invalidSeverity.total;
    root-render-fallback =
      krisis.safeRender poison == "<unrenderable value>"
      && krisis.safeShape poison == "<unrenderable value>"
      && krisis.safeRenderWith { fallback = "hidden"; } poison == "hidden";
    invalid-options-all-branches =
      throws (krisis.safeRenderWith { maxListItems = -1; } (_: poison))
      && throws (krisis.safeShapeWith { maxAttrs = -1; } (_: poison))
      && throws (krisis.safeRenderWith { maxListItems = -1; } poison);
    truncated-tail-lazy =
      krisis.safeRenderWith { maxListItems = 1; } [
        1
        poison
      ] == "[1] (+1 more)";
    zero-prefix-lazy = krisis.safeRenderWith { maxListItems = 0; } [ poison ] == "[] (+1 more)";
    derivation-name-fallback =
      krisis.safeRender {
        type = "derivation";
        name = poison;
        outPath = poison;
      } == "<derivation ?>";
    suggestion-equivalence =
      lib.all (input: krisis.suggest input candidates == oldSuggest input candidates)
        [
          "foo"
          "fou"
          "baz"
          "barrels"
          "unrelated"
          ""
        ];
    suggestion-ties =
      krisis.suggest "cat" [
        "bat"
        "car"
      ] == "bat";
    suggestion-threshold =
      krisis.suggest "abc" [ "def" ] == null
      && krisis.suggestWith { maxDistance = 3; } "abc" [ "def" ] == "def";
    suggestion-errors =
      throws (krisis.suggestWith { maxDistance = -1; } "x" [ ]) && throws (krisis.suggest "x" [ 1 ]);
    edit-distance-delegates = krisis.editDistance "kitten" "sitting" == 3;
  };
in
lib.mapAttrsToList (name: pass: { inherit name pass; }) evidence
