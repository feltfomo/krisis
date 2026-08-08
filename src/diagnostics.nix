{
  lib,
  validation,
  schema,
  canonical,
}:
let
  allowedSeverities = [
    "error"
    "warning"
    "info"
  ];

  invalid =
    field: expected: value:
    "diagnostic ${field} must be ${expected}; got ${builtins.typeOf value}";

  # krisis has nobody to hand accumulated diagnostics back to -- a malformed
  # diagnostic record is malformed direct use of this library, so accumulation
  # always ends in one throw
  failKrisis = diagnostics: throw "krisis: ${lib.concatStringsSep "; " diagnostics}";

  finish = validation.finish failKrisis;

  stringField = subject: {
    validate = builtins.isString;
    onInvalid = _record: value: invalid subject "a string" value;
  };

  labelSchema =
    subject: names:
    schema.compile {
      onRecord = value: invalid subject "an attribute set" value;
      onUnknown = name: _value: "diagnostic ${subject} does not accept field '${name}'";
      order = names;
      fields = lib.genAttrs names (name: stringField "${subject}.${name}");
    };

  primaryDiagnostics = primary: (labelSchema "primary" [ "label" "source" ] primary).diagnostics;

  secondaryDiagnostics =
    index: secondary:
    let
      subject = "secondaryLabels[${toString index}]";
      shape = labelSchema subject [
        "label"
        "source"
        "message"
      ];
      identified = builtins.isAttrs secondary && (secondary ? label || secondary ? source);
    in
    validation.collect [
      (shape secondary).diagnostics
      (validation.optional (
        builtins.isAttrs secondary && !identified
      ) "diagnostic ${subject} must identify a label or source")
    ];

  secondaryLabelDiagnostics =
    labels:
    if !builtins.isList labels then
      [ (invalid "secondaryLabels" "a list" labels) ]
    else
      validation.collect (lib.imap0 secondaryDiagnostics labels);

  noteDiagnostics =
    notes:
    validation.optional (!builtins.isList notes || !lib.all builtins.isString notes) (
      invalid "notes" "a list of strings" notes
    );

  # an explicit null in an optional field has always meant absent here, and
  # dropping it before the schema runs keeps that
  nullableFields = [
    "primary"
    "secondaryLabels"
    "notes"
    "help"
  ];

  withoutNulls =
    args:
    removeAttrs args (builtins.filter (name: args ? ${name} && args.${name} == null) nullableFields);

  diagnosticSchema = schema.compile {
    onRecord = value: invalid "record" "an attribute set" value;
    onUnknown = name: _value: "diagnostic does not accept field '${name}'";
    order = [
      "severity"
      "code"
      "message"
      "primary"
      "secondaryLabels"
      "notes"
      "help"
      "context"
    ];
    fields = {
      severity = {
        required = true;
        onMissing = _record: "diagnostic is missing required field 'severity'";
        validate = value: builtins.isString value && builtins.elem value allowedSeverities;
        onInvalid =
          _record: value:
          if builtins.isString value then
            "diagnostic severity '${value}' is not one of ${lib.concatStringsSep ", " allowedSeverities}"
          else
            invalid "severity" "a string" value;
      };
      code = {
        required = true;
        onMissing = _record: "diagnostic is missing required field 'code'";
        validate = value: builtins.isString value && value != "";
        onInvalid =
          _record: value:
          if builtins.isString value then
            "diagnostic code must not be empty"
          else
            invalid "code" "a string" value;
      };
      message = stringField "message" // {
        required = true;
        onMissing = _record: "diagnostic is missing required field 'message'";
      };
      primary = { };
      secondaryLabels = { };
      notes = { };
      help = stringField "help";
      context = { };
    };
  };

  mkDiagnostic =
    args:
    let
      record = if builtins.isAttrs args then withoutNulls args else args;
      shape = diagnosticSchema record;
      nested = lib.optionals (builtins.isAttrs record) (
        validation.collect [
          (lib.optionals (record ? primary) (primaryDiagnostics record.primary))
          (lib.optionals (record ? secondaryLabels) (secondaryLabelDiagnostics record.secondaryLabels))
          (lib.optionals (record ? notes) (noteDiagnostics record.notes))
        ]
      );
      diagnostics = validation.collect [
        shape.diagnostics
        nested
      ];
    in
    finish (validation.fromDiagnostics diagnostics (shape.value or null));

  qualifyCode =
    prefix: code:
    if prefix != null && !builtins.isString prefix then
      failKrisis [ (invalid "code prefix" "a string or null" prefix) ]
    else if !builtins.isString code then
      failKrisis [ (invalid "code" "a string" code) ]
    else if code == "" then
      failKrisis [ "diagnostic code must not be empty" ]
    else if prefix == null || prefix == "" then
      code
    else
      canonical.qualified {
        namespace = prefix;
        name = code;
      };

  factorySchema = schema.compile {
    onRecord = value: invalid "factory defaults" "an attribute set" value;
    onUnknown = name: _value: "diagnostic factory does not accept field '${name}'";
    order = [
      "severity"
      "codePrefix"
      "primary"
    ];
    fields = {
      severity.default = "error";
      codePrefix.default = null;
      primary.default = null;
    };
  };

  mkDiagnosticFactory =
    defaults:
    let
      resolved = finish (factorySchema defaults);
    in
    builtins.seq resolved (
      args:
      if !builtins.isAttrs args then
        failKrisis [ (invalid "factory input" "an attribute set" args) ]
      else
        let
          callPrimary = args.primary or null;
          primary =
            if resolved.primary == null then
              callPrimary
            else if callPrimary == null then
              resolved.primary
            else
              resolved.primary // callPrimary;
        in
        mkDiagnostic (
          (removeAttrs args [
            "severity"
            "code"
            "primary"
          ])
          // {
            severity = args.severity or resolved.severity;
            code = qualifyCode resolved.codePrefix (args.code or null);
          }
          // lib.optionalAttrs (primary != null) { inherit primary; }
        )
    );

  rendererSchema = schema.compile {
    onRecord = value: invalid "renderer arguments" "an attribute set" value;
    onUnknown = name: _value: "diagnostic renderer does not accept field '${name}'";
    order = [
      "diagnostics"
      "formatDiagnostic"
      "formatHeader"
      "separator"
    ];
    fields = {
      diagnostics = {
        required = true;
        onMissing = _record: "diagnostic renderer is missing required field 'diagnostics'";
        validate = builtins.isList;
        onInvalid = _record: value: invalid "list" "a list" value;
      };
      formatDiagnostic = {
        required = true;
        onMissing = _record: "diagnostic renderer is missing required field 'formatDiagnostic'";
        validate = builtins.isFunction;
        onInvalid = _record: value: invalid "formatDiagnostic" "a function" value;
      };
      formatHeader = {
        default = _count: null;
        validate = builtins.isFunction;
        onInvalid = _record: value: invalid "formatHeader" "a function" value;
      };
      separator = {
        default = "\n";
        validate = builtins.isString;
        onInvalid = _record: value: invalid "separator" "a string" value;
      };
    };
  };

  renderDiagnostics =
    args:
    let
      config = finish (rendererSchema args);
      header = config.formatHeader (builtins.length config.diagnostics);
      parts = lib.optional (header != null) header ++ map config.formatDiagnostic config.diagnostics;
    in
    if header != null && !builtins.isString header then
      failKrisis [ (invalid "header" "a string or null" header) ]
    else if !lib.all builtins.isString parts then
      failKrisis [ "diagnostic formatters must return strings" ]
    else
      lib.concatStringsSep config.separator parts;

  throwDiagnostics = args: throw (renderDiagnostics args);

  # stock one-diagnostic text for subsystems without their own format -- code,
  # optional primary label, and message on the first line, notes and help
  # indented beneath.
  renderPlain =
    diagnostic:
    let
      subject = diagnostic.primary.label or null;
      head =
        "[${diagnostic.code}]"
        + lib.optionalString (subject != null) " ${subject}:"
        + " ${diagnostic.message}";
    in
    lib.concatStringsSep "\n" (
      [ head ]
      ++ map (note: "    note: ${note}") (diagnostic.notes or [ ])
      ++ lib.optional (diagnostic ? help) "    help: ${diagnostic.help}"
    );

  mkReporter =
    {
      formatDiagnostic,
      formatHeader ? (_count: null),
      separator ? "\n",
    }:
    let
      render =
        diagnostics:
        renderDiagnostics {
          inherit
            diagnostics
            formatDiagnostic
            formatHeader
            separator
            ;
        };
      fail = diagnostics: throw (render diagnostics);
    in
    {
      inherit render fail;
      renderOne = diagnostic: render [ diagnostic ];
      failOne = diagnostic: fail [ diagnostic ];
      checked = diagnostics: value: if diagnostics == [ ] then value else fail diagnostics;
    };

  collectDiagnostics =
    groups:
    if !builtins.isList groups || !lib.all builtins.isList groups then
      failKrisis [ (invalid "groups" "a list of diagnostic lists" groups) ]
    else
      validation.collect groups;

  optionalDiagnostic =
    condition: diagnostic:
    if !builtins.isBool condition then
      failKrisis [ (invalid "optional diagnostic condition" "a boolean" condition) ]
    else
      validation.optional condition diagnostic;

  withErrorContext =
    message: value:
    if !builtins.isString message then
      failKrisis [ (invalid "error context" "a string" message) ]
    else
      builtins.addErrorContext message value;
in
{
  inherit
    allowedSeverities
    qualifyCode
    mkDiagnostic
    mkDiagnosticFactory
    renderDiagnostics
    throwDiagnostics
    renderPlain
    mkReporter
    collectDiagnostics
    optionalDiagnostic
    withErrorContext
    ;
}
