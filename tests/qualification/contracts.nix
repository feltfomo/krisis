{ fx }:
let
  poison = throw "deferred presentation";
  make =
    options:
    let
      unknown = builtins.filter (
        name:
        !(builtins.elem name [
          "code"
          "severity"
          "message"
          "location"
          "context"
        ])
      ) (builtins.attrNames options);
      envelope =
        builtins.isString options.code
        && options.code != ""
        && builtins.elem options.severity [
          "error"
          "warning"
          "info"
        ];
    in
    if unknown != [ ] then
      throw "unknown diagnostic option"
    else if !envelope then
      throw "invalid diagnostic envelope"
    else
      options;
  project =
    diagnostic:
    if builtins.isString diagnostic.message then
      { inherit (diagnostic) code severity message; }
    else
      throw "message must be a string";
  policy =
    {
      promote ? false,
      suppress ? [ ],
      minimum ? "info",
    }:
    diagnostic:
    let
      effective = if promote && diagnostic.severity == "warning" then "error" else diagnostic.severity;
      rank = {
        info = 0;
        warning = 1;
        error = 2;
      };
      failed = effective == "error";
    in
    {
      inherit effective failed;
      count = 1;
      visible = !(builtins.elem diagnostic.code suppress) && rank.${effective} >= rank.${minimum};
    };
  diagnostic = make {
    code = "test";
    severity = "warning";
    message = poison;
    location = poison;
    context = poison;
  };
  H = fx.types.hoas;
  checked = H.datatype "Checked" [
    (H.con "Valid" [ (H.field "value" (H.thunk H.any)) ])
    (H.con "Invalid" [ ])
  ];
  outcome = H.datatype "Outcome" [
    (H.con "Success" [ (H.field "value" (H.thunk H.any)) ])
    (H.con "Failure" [ ])
  ];
in
{
  test-envelope-defers = {
    expr = diagnostic.code;
    expected = "test";
  };
  test-unknown-option = {
    expr =
      (make {
        code = "test";
        severity = "warning";
        message = poison;
        extra = poison;
      }).code;
    expectedError = {
      type = "ThrownError";
      msg = "unknown diagnostic option";
    };
  };
  test-requested-presentation = {
    expr = project (make {
      code = "test";
      severity = "warning";
      message = 1;
      context = poison;
    });
    expectedError = {
      type = "ThrownError";
      msg = "message must be a string";
    };
  };
  test-projection-excludes-context = {
    expr = project (make {
      code = "test";
      severity = "warning";
      message = "visible";
      context = poison;
      location = poison;
    });
    expected = {
      code = "test";
      severity = "warning";
      message = "visible";
    };
  };
  test-promotion-before-suppression = {
    expr = policy {
      promote = true;
      suppress = [ "test" ];
      minimum = "error";
    } diagnostic;
    expected = {
      effective = "error";
      failed = true;
      count = 1;
      visible = false;
    };
  };
  test-warning-success = {
    expr = policy { minimum = "error"; } diagnostic;
    expected = {
      effective = "warning";
      failed = false;
      count = 1;
      visible = false;
    };
  };
  test-suppressed-error-fails = {
    expr = policy { suppress = [ "test" ]; } (diagnostic // { severity = "error"; });
    expected = {
      effective = "error";
      failed = true;
      count = 1;
      visible = false;
    };
  };
  test-generated-shapes = {
    expr = {
      checked = map (c: {
        inherit (c) name;
        fields = map (f: f.name) c.fields;
      }) (fx.types.generic.datatype.datatypeInfo checked.T).constructors;
      outcome = map (c: {
        inherit (c) name;
        fields = map (f: f.name) c.fields;
      }) (fx.types.generic.datatype.datatypeInfo outcome.T).constructors;
    };
    expected = {
      checked = [
        {
          name = "Valid";
          fields = [ "value" ];
        }
        {
          name = "Invalid";
          fields = [ ];
        }
      ];
      outcome = [
        {
          name = "Success";
          fields = [ "value" ];
        }
        {
          name = "Failure";
          fields = [ ];
        }
      ];
    };
  };
}
