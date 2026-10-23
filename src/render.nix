{
  lib,
  diagnostic,
  path,
}:
let
  project =
    raw:
    let
      d = diagnostic.make raw;
      presentation = {
        inherit (d)
          severity
          code
          message
          primary
          related
          notes
          help
          ;
      };
    in
    builtins.deepSeq presentation presentation;
  events =
    report:
    lib.zipListsWith (d: decision: { inherit d decision; }) report.diagnostics report.visibility;
  projectEvent =
    event:
    (project event.d)
    // {
      severity = event.decision.effectiveSeverity;
      inherit (event.decision) originalSeverity effectiveSeverity;
    };
  projectReport =
    report:
    let
      projection = {
        schemaVersion = 1;
        kind = "report";
        diagnostics = map projectEvent (builtins.filter (event: event.decision.visible) (events report));
        summary = {
          inherit (report.summary) total hasErrors;
          bySeverity = { inherit (report.summary.bySeverity) error warning info; };
          # code strings can be Nix coercion keys such as __toString or outPath
          byCode = map (code: {
            inherit code;
            count = report.summary.byCode.${code};
          }) (builtins.attrNames report.summary.byCode);
        };
        outcome = {
          status = report.outcome._con;
        };
      };
    in
    builtins.deepSeq projection projection;
  point = p: "${toString p.line}:${toString p.column}";
  location =
    l:
    lib.concatStringsSep " " (
      lib.optional (l.label != null) l.label
      ++ lib.optional (l.source != null) (
        l.source + lib.optionalString (l.range != null) ":${point l.range.start}-${point l.range.end}"
      )
      ++ lib.optional (l.path != [ ]) (path.render l.path)
    );
  indent = prefix: text: lib.replaceStrings [ "\n" ] [ "\n${prefix}" ] text;
  plainProjection =
    d:
    lib.concatStringsSep "\n" (
      [
        "${d.severity} [${d.code}]${
          lib.optionalString (d.primary != null) " ${location d.primary}:"
        } ${indent "    " d.message}"
      ]
      ++ map (
        r:
        "    related: ${indent "        " (location r.location)}${
              lib.optionalString (r.message != null) ": ${indent "        " r.message}"
            }"
      ) d.related
      ++ map (note: "    note: ${indent "        " note}") d.notes
      ++ lib.optional (d.help != null) "    help: ${indent "        " d.help}"
    );
  custom =
    formatter: raw:
    let
      projection = project raw;
      result = builtins.addErrorContext "while formatting a Krisis diagnostic" (
        builtins.seq projection (formatter projection)
      );
    in
    if !builtins.isFunction formatter then
      throw "krisis: formatter must be a function"
    else if !builtins.isString result then
      throw "krisis: formatter must return a string"
    else
      result;
  customReport =
    formatter: report:
    let
      projection = projectReport report;
      result = builtins.addErrorContext "while formatting a Krisis report" (
        builtins.seq projection (formatter projection)
      );
    in
    if !builtins.isFunction formatter then
      throw "krisis: formatter must be a function"
    else if !builtins.isString result then
      throw "krisis: formatter must return a string"
    else
      result;
  plain = custom plainProjection;
  plainReport = customReport (p: lib.concatMapStringsSep "\n" plainProjection p.diagnostics);
  blocking =
    report: lib.concatMapStringsSep "\n" (event: plainProjection (projectEvent event)) (events report);
in
{
  inherit
    project
    projectReport
    plain
    plainReport
    custom
    customReport
    ;
  json =
    raw:
    builtins.toJSON {
      schemaVersion = 1;
      kind = "diagnostic";
      diagnostic = project raw;
    };
  jsonReport = report: builtins.toJSON (projectReport report);
  # module failure explanations include retained events regardless of display policy
  inherit blocking;
}
