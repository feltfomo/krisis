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
    in
    builtins.deepSeq (removeAttrs d [ "context" ]) (removeAttrs d [ "context" ]);
  plain =
    raw:
    let
      d = project raw;
      where =
        if d.primary == null then
          ""
        else
          (
            if d.primary.label != null then
              d.primary.label
            else if d.primary.source != null then
              d.primary.source
            else
              path.render d.primary.path
          );
    in
    lib.concatStringsSep "\n" (
      [ "${d.severity} [${d.code}]${lib.optionalString (where != "") " ${where}:"} ${d.message}" ]
      ++ map (note: "    note: ${note}") d.notes
      ++ lib.optional (d.help != null) "    help: ${d.help}"
    );
in
{
  inherit project plain;
}
