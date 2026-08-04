{ lib }:
let
  allowedSeverities = [
    "error"
    "warning"
    "info"
  ];

  invalid =
    field: expected: value:
    throw "krisis: diagnostic ${field} must be ${expected}; got ${builtins.typeOf value}";

  validateFields =
    subject: allowed: value:
    let
      unknown = builtins.filter (name: !(builtins.elem name allowed)) (builtins.attrNames value);
    in
    if unknown == [ ] then
      true
    else
      throw "krisis: ${subject} accepts only ${lib.concatStringsSep ", " allowed}; got ${lib.concatStringsSep ", " unknown}";

  validatePrimary =
    primary:
    if !builtins.isAttrs primary then
      invalid "primary" "an attribute set" primary
    else
      builtins.seq
        (validateFields "diagnostic primary" [
          "label"
          "source"
        ] primary)
        (
          if primary ? label && !builtins.isString primary.label then
            invalid "primary.label" "a string" primary.label
          else if primary ? source && !builtins.isString primary.source then
            invalid "primary.source" "a string" primary.source
          else
            primary
        );

  validateSecondary =
    index: secondary:
    if !builtins.isAttrs secondary then
      invalid "secondaryLabels[${toString index}]" "an attribute set" secondary
    else
      builtins.seq
        (validateFields "diagnostic secondaryLabels[${toString index}]" [
          "label"
          "source"
          "message"
        ] secondary)
        (
          if secondary ? label && !builtins.isString secondary.label then
            invalid "secondaryLabels[${toString index}].label" "a string" secondary.label
          else if secondary ? source && !builtins.isString secondary.source then
            invalid "secondaryLabels[${toString index}].source" "a string" secondary.source
          else if secondary ? message && !builtins.isString secondary.message then
            invalid "secondaryLabels[${toString index}].message" "a string" secondary.message
          else if !(secondary ? label) && !(secondary ? source) then
            throw "krisis: diagnostic secondaryLabels[${toString index}] must identify a label or source"
          else
            secondary
        );

  validateSecondaryLabels =
    labels:
    if !builtins.isList labels then
      invalid "secondaryLabels" "a list" labels
    else
      lib.imap0 validateSecondary labels;

  validateNotes =
    notes:
    if !builtins.isList notes then
      invalid "notes" "a list of strings" notes
    else if !lib.all builtins.isString notes then
      invalid "notes" "a list of strings" notes
    else
      notes;

  qualifyCode =
    prefix: code:
    if prefix != null && !builtins.isString prefix then
      invalid "code prefix" "a string or null" prefix
    else if !builtins.isString code then
      invalid "code" "a string" code
    else if code == "" then
      throw "krisis: diagnostic code must not be empty"
    else if prefix == null || prefix == "" then
      code
    else
      "${prefix}/${code}";

  mkDiagnostic =
    args:
    if !builtins.isAttrs args then
      invalid "record" "an attribute set" args
    else
      let
        allowed = [
          "severity"
          "code"
          "message"
          "primary"
          "secondaryLabels"
          "notes"
          "help"
          "context"
        ];
        required = [
          "severity"
          "code"
          "message"
        ];
        missing = builtins.filter (name: !(args ? ${name})) required;
        validFields = validateFields "diagnostic" allowed args;
        severity = args.severity or null;
        code = args.code or null;
        message = args.message or null;
        primary = args.primary or null;
        secondaryLabels =
          if args ? secondaryLabels then validateSecondaryLabels args.secondaryLabels else null;
        notes = if args ? notes then validateNotes args.notes else null;
        help = args.help or null;
        validCore =
          if missing != [ ] then
            throw "krisis: diagnostic is missing required fields ${lib.concatStringsSep ", " missing}"
          else if !builtins.isString severity then
            invalid "severity" "a string" severity
          else if !(builtins.elem severity allowedSeverities) then
            throw "krisis: diagnostic severity '${severity}' is not one of ${lib.concatStringsSep ", " allowedSeverities}"
          else if !builtins.isString code then
            invalid "code" "a string" code
          else if code == "" then
            throw "krisis: diagnostic code must not be empty"
          else if !builtins.isString message then
            invalid "message" "a string" message
          else
            true;
        validOptionals = builtins.seq (if primary == null then true else validatePrimary primary) (
          builtins.seq (if secondaryLabels == null then true else builtins.deepSeq secondaryLabels true) (
            builtins.seq (if notes == null then true else builtins.deepSeq notes true) (
              if help == null || builtins.isString help then true else invalid "help" "a string" help
            )
          )
        );
      in
      builtins.seq validFields (
        builtins.seq validCore (
          builtins.seq validOptionals (
            {
              inherit severity code message;
            }
            // lib.optionalAttrs (primary != null) { primary = validatePrimary primary; }
            // lib.optionalAttrs (secondaryLabels != null) { inherit secondaryLabels; }
            // lib.optionalAttrs (notes != null) { inherit notes; }
            // lib.optionalAttrs (help != null) { inherit help; }
            // lib.optionalAttrs (args ? context) { inherit (args) context; }
          )
        )
      );

  mkDiagnosticFactory =
    defaults:
    if !builtins.isAttrs defaults then
      invalid "factory defaults" "an attribute set" defaults
    else
      let
        allowed = [
          "severity"
          "codePrefix"
          "primary"
        ];
        validFields = validateFields "diagnostic factory" allowed defaults;
        defaultSeverity = defaults.severity or "error";
        codePrefix = defaults.codePrefix or null;
        defaultPrimary = defaults.primary or null;
      in
      builtins.seq validFields (
        args:
        if !builtins.isAttrs args then
          invalid "factory input" "an attribute set" args
        else
          let
            callPrimary = args.primary or null;
            primary =
              if defaultPrimary == null then
                callPrimary
              else if callPrimary == null then
                defaultPrimary
              else
                defaultPrimary // callPrimary;
          in
          mkDiagnostic (
            (removeAttrs args [
              "severity"
              "code"
              "primary"
            ])
            // {
              severity = args.severity or defaultSeverity;
              code = qualifyCode codePrefix (args.code or null);
            }
            // lib.optionalAttrs (primary != null) { inherit primary; }
          )
      );

  renderDiagnostics =
    {
      diagnostics,
      formatDiagnostic,
      formatHeader ? (_count: null),
      separator ? "\n",
    }:
    if !builtins.isList diagnostics then
      invalid "list" "a list" diagnostics
    else if !builtins.isFunction formatDiagnostic then
      invalid "formatDiagnostic" "a function" formatDiagnostic
    else if !builtins.isFunction formatHeader then
      invalid "formatHeader" "a function" formatHeader
    else if !builtins.isString separator then
      invalid "separator" "a string" separator
    else
      let
        header = formatHeader (builtins.length diagnostics);
        parts = lib.optional (header != null) header ++ map formatDiagnostic diagnostics;
      in
      if header != null && !builtins.isString header then
        invalid "header" "a string or null" header
      else if !lib.all builtins.isString parts then
        throw "krisis: diagnostic formatters must return strings"
      else
        lib.concatStringsSep separator parts;

  throwDiagnostics = args: throw (renderDiagnostics args);

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
      invalid "groups" "a list of diagnostic lists" groups
    else
      builtins.concatLists groups;

  optionalDiagnostic = condition: diagnostic: lib.optional condition diagnostic;

  withErrorContext =
    message: value:
    if !builtins.isString message then
      invalid "error context" "a string" message
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
    mkReporter
    collectDiagnostics
    optionalDiagnostic
    withErrorContext
    ;
}
