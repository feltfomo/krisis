{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  poison = throw "presentation poison";
  diagnostic = {
    code = "range";
    severity = "warning";
    message = "first line\nsecond line";
    primary = {
      label = "service";
      source = "config.nix";
      path = [
        (k.path.field "a.b")
        (k.path.index 2)
        (k.path.variant "Some")
      ];
      range = {
        start = {
          line = 2;
          column = 3;
        };
        end = {
          line = 4;
          column = 5;
        };
      };
    };
    related = [
      {
        location = {
          label = "other";
          source = "other.nix";
          path = [ (k.path.field "if") ];
        };
        message = "also here\nnext line";
      }
      { location.source = "third.nix"; }
    ];
    notes = [ "one\ntwo" ];
    help = "change it\nthen retry";
    context = poison;
  };
  report = k.report.run { policy.warningsAsErrors = true; } (k.report.emit diagnostic);
  hidden = k.report.run { policy.suppressCodes = [ "range" ]; } (
    k.report.emit (
      diagnostic
      // {
        message = poison;
        severity = "error";
      }
    )
  );
  opaque = k.report.run { } (fx.pure poison);
  decoded = builtins.fromJSON (k.render.jsonReport report);
  error = expr: {
    inherit expr;
    expectedError.type = "ThrownError";
  };
in
{
  test-multiline-golden = {
    expr = k.render.plain diagnostic;
    expected = ''
      warning [range] service config.nix:2:3-4:5 $."a.b"[2]#"Some": first line
          second line
          related: other other.nix $."if": also here
              next line
          related: third.nix
          note: one
              two
          help: change it
              then retry'';
  };
  test-omitted-golden = {
    expr = k.render.plain {
      code = "minimal";
      message = "message";
    };
    expected = "error [minimal] message";
  };
  test-location-path-only = {
    expr = k.render.plain {
      code = "path";
      message = "x";
      primary.path = [ (k.path.field "") ];
    };
    expected = ''error [path] $."": x'';
  };
  test-zero-length-range = {
    expr = k.render.plain {
      code = "point";
      message = "x";
      primary = {
        source = "x";
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
    };
    expected = "error [point] x:1:1-1:1: x";
  };
  test-json-diagnostic-roundtrip = {
    expr = builtins.fromJSON (k.render.json diagnostic);
    expected = {
      schemaVersion = 1;
      kind = "diagnostic";
      diagnostic = k.render.project diagnostic;
    };
  };
  test-json-normalized-defaults = {
    expr = builtins.fromJSON (
      k.render.json {
        code = "x";
        message = "x";
      }
    );
    expected = {
      schemaVersion = 1;
      kind = "diagnostic";
      diagnostic = {
        code = "x";
        message = "x";
        severity = "error";
        primary = null;
        related = [ ];
        notes = [ ];
        help = null;
      };
    };
  };
  test-promoted-severities = {
    expr = map (d: { inherit (d) severity originalSeverity effectiveSeverity; }) decoded.diagnostics;
    expected = [
      {
        severity = "error";
        originalSeverity = "warning";
        effectiveSeverity = "error";
      }
    ];
  };
  test-report-allowlist = {
    expr = builtins.attrNames decoded;
    expected = [
      "diagnostics"
      "kind"
      "outcome"
      "schemaVersion"
      "summary"
    ];
  };
  test-diagnostic-allowlist = {
    expr = builtins.attrNames (builtins.head decoded.diagnostics);
    expected = [
      "code"
      "effectiveSeverity"
      "help"
      "message"
      "notes"
      "originalSeverity"
      "primary"
      "related"
      "severity"
    ];
  };
  test-outcome-allowlist = {
    expr = (builtins.fromJSON (k.render.jsonReport opaque)).outcome;
    expected.status = "Success";
  };
  test-report-hidden-poison = {
    expr = (builtins.fromJSON (k.render.jsonReport hidden)).diagnostics;
    expected = [ ];
  };
  test-hidden-counts-unchanged = {
    expr = (builtins.fromJSON (k.render.jsonReport hidden)).summary;
    expected = hidden.summary // {
      byCode = [
        {
          code = "range";
          count = 1;
        }
      ];
    };
  };
  test-hidden-failure-unchanged = {
    expr = (builtins.fromJSON (k.render.jsonReport hidden)).outcome;
    expected.status = "Failure";
  };
  test-threshold = {
    expr =
      (k.render.projectReport (
        k.report.run { policy.minimumSeverity = "error"; } (k.report.emit diagnostic)
      )).diagnostics;
    expected = [ ];
  };
  test-repeated-json = {
    expr = k.render.jsonReport report == k.render.jsonReport report;
    expected = true;
  };
  test-order = {
    expr =
      map (d: d.code)
        (builtins.fromJSON (
          k.render.jsonReport (
            k.report.run { } (
              fx.bind
                (k.report.emit {
                  code = "z";
                  message = "z";
                })
                (
                  _:
                  k.report.emit {
                    code = "a";
                    message = "a";
                  }
                )
            )
          )
        )).diagnostics;
    expected = [
      "z"
      "a"
    ];
  };
  test-config-opaque = {
    expr =
      let
        config = {
          message = "safe";
          unused = poison;
        };
      in
      k.render.plain {
        code = "safe";
        inherit (config) message;
        context = config;
      };
    expected = "error [safe] safe";
  };
  test-report-plain = {
    expr = k.render.plainReport report;
    expected = lib.replaceStrings [ "warning [range]" ] [ "error [range]" ] (k.render.plain diagnostic);
  };
  test-report-plain-hidden = {
    expr = k.render.plainReport hidden;
    expected = "";
  };
  test-custom-projection-only = {
    expr = k.render.custom builtins.attrNames diagnostic;
    expectedError = {
      type = "ThrownError";
      msg = "formatter must return a string";
    };
  };
  test-custom-context-absent = {
    expr = k.render.custom (p: toString (p ? context)) diagnostic;
    expected = "";
  };
  test-custom-result = error (k.render.custom (_: 1) diagnostic);
  test-custom-control = error (k.render.custom 1 diagnostic);
  test-custom-original-error = {
    expr = k.render.custom (_: throw "original formatter error") diagnostic;
    expectedError = {
      type = "ThrownError";
      msg = "original formatter error";
    };
  };
  test-custom-report-no-value = {
    expr = k.render.customReport (p: p.outcome.status) opaque;
    expected = "Success";
  };
  test-custom-report-result = error (k.render.customReport (_: null) opaque);
  test-custom-report-original-error = {
    expr = k.render.customReport (_: throw "original report formatter") opaque;
    expectedError = {
      type = "ThrownError";
      msg = "original report formatter";
    };
  };
  test-strict-complete-renderer = {
    expr = k.report.run {
      mode = "strict";
      policy.warningsAsErrors = true;
    } (k.report.emit diagnostic);
    expectedError = {
      type = "ThrownError";
      msg = "other.nix";
    };
  };
  test-strict-custom = {
    expr = k.report.run {
      mode = "strict";
      formatter = p: "custom ${p.code}";
    } (k.report.fail diagnostic);
    expectedError = {
      type = "ThrownError";
      msg = "custom range";
    };
  };
  test-strict-custom-result = error (
    k.report.run {
      mode = "strict";
      formatter = _: false;
    } (k.report.fail diagnostic)
  );
  test-reserved-code-counts = {
    expr =
      (builtins.fromJSON (
        k.render.jsonReport (
          k.report.run { } (
            fx.bind
              (k.report.emit {
                code = "__toString";
                message = "x";
              })
              (
                _:
                k.report.emit {
                  code = "outPath";
                  message = "x";
                }
              )
          )
        )
      )).summary.byCode;
    expected = [
      {
        code = "__toString";
        count = 1;
      }
      {
        code = "outPath";
        count = 1;
      }
    ];
  };
  test-custom-validates-complete-projection = error (
    k.render.custom (_: "ignored") (diagnostic // { help = 1; })
  );
  test-custom-report-validates-complete-projection = error (
    k.render.customReport (_: "ignored") (
      k.report.run { } (k.report.emit (diagnostic // { help = 1; }))
    )
  );
  test-strict-custom-original-error = {
    expr = k.report.run {
      mode = "strict";
      formatter = _: throw "strict formatter original";
    } (k.report.fail diagnostic);
    expectedError = {
      type = "ThrownError";
      msg = "strict formatter original";
    };
  };
  test-related-source-range = {
    expr = k.render.plain {
      code = "related";
      message = "x";
      related = [
        {
          location = {
            source = "other.nix";
            label = "declaration";
            path = [ (k.path.field "x") ];
            range = {
              start = {
                line = 1;
                column = 2;
              };
              end = {
                line = 2;
                column = 3;
              };
            };
          };
        }
      ];
    };
    expected = "error [related] x\n    related: declaration other.nix:1:2-2:3 $.x";
  };
  test-validation-json-omits-context = {
    expr =
      map (d: d ? context)
        (builtins.fromJSON (k.render.jsonReport (import ../examples/basic.nix { inherit lib fx; })))
        .diagnostics;
    expected = [ false ];
  };
  test-report-unrelated-config = {
    expr =
      let
        config = {
          message = "safe";
          unrelated = poison;
        };
      in
      (builtins.fromJSON (
        k.render.jsonReport (
          k.report.run { } (
            k.report.emit {
              code = "safe";
              inherit (config) message;
              context = config;
            }
          )
        )
      )).diagnostics;
    expected = [
      (
        (k.render.project {
          code = "safe";
          message = "safe";
        })
        // {
          originalSeverity = "error";
          effectiveSeverity = "error";
        }
      )
    ];
  };
  test-json-deferred-checks = error (k.render.json (diagnostic // { help = 1; }));
  test-json-range-checks = error (
    k.render.json (
      diagnostic
      // {
        primary = {
          source = "x";
          range = {
            start = {
              line = 0;
              column = 1;
            };
            end = {
              line = 1;
              column = 1;
            };
          };
        };
      }
    )
  );
}
