{
  fx,
  types,
  path,
}:
let
  inherit (types) expect closed;
  T = fx.types;
  qualify =
    namespace: code:
    builtins.seq (expect "namespace" (T.Maybe types.nonempty) namespace) (
      builtins.seq (expect "code" types.nonempty code) (
        if namespace == null then code else "${namespace}/${code}"
      )
    );
  location =
    raw:
    let
      args = closed "location" [ "label" "source" "path" "range" ] raw;
      normalized = {
        label = null;
        source = null;
        range = null;
      }
      // args
      // {
        path = path.normalize (args.path or [ ]);
      };
    in
    builtins.seq args (builtins.seq normalized.path (expect "location" types.location normalized));
  make =
    raw:
    let
      args = closed "diagnostic" [
        "severity"
        "code"
        "message"
        "primary"
        "related"
        "notes"
        "help"
        "context"
      ] raw;
      envelope = expect "diagnostic envelope" types.envelope {
        severity = args.severity or "error";
        code = args.code or null;
      };
      body = removeAttrs args [ "context" ];
    in
    builtins.seq envelope (
      if !(args ? message) then
        throw "krisis: diagnostic requires message"
      else
        {
          inherit (envelope) code severity;
          message = expect "message" T.String body.message;
          primary = if (body.primary or null) == null then null else location body.primary;
          related =
            let
              values = body.related or [ ];
            in
            if !builtins.isList values then
              throw "krisis: invalid related"
            else
              map (
                rawRelated:
                let
                  r = closed "related" [ "location" "message" ] rawRelated;
                in
                {
                  location = location (r.location or (throw "krisis: related requires location"));
                  message = expect "related message" (T.Maybe T.String) (r.message or null);
                }
              ) values;
          notes = expect "notes" (T.ListOf T.String) (body.notes or [ ]);
          help = expect "help" (T.Maybe T.String) (body.help or null);
          context = args.context or null;
        }
    );
  defaults =
    raw:
    let
      args = closed "defaults" [ "namespace" "severity" "primary" ] raw;
    in
    builtins.deepSeq
      {
        namespace = expect "namespace" (T.Maybe types.nonempty) (args.namespace or null);
        severity = expect "default severity" types.severity (args.severity or "error");
      }
      (
        {
          namespace = null;
          severity = "error";
          primary = null;
        }
        // args
      );
  mergeLocation =
    base: call:
    if call == null then
      null
    else if base == null then
      call
    else
      base // call;
  mergeDefaults = parent: child: {
    namespace = child.namespace or parent.namespace;
    severity = child.severity or parent.severity;
    primary = if child ? primary then mergeLocation parent.primary child.primary else parent.primary;
  };
  applyDefaults =
    config: args:
    make (
      args
      // {
        severity = args.severity or config.severity;
        code = qualify config.namespace (args.code or null);
        primary = if args ? primary then mergeLocation config.primary args.primary else config.primary;
      }
    );
  factory =
    raw:
    let
      config = defaults raw;
    in
    builtins.seq config (
      args:
      applyDefaults config (
        closed "diagnostic" [
          "severity"
          "code"
          "message"
          "primary"
          "related"
          "notes"
          "help"
          "context"
        ] args
      )
    );
in
{
  inherit
    make
    factory
    location
    defaults
    mergeDefaults
    applyDefaults
    ;
  types = {
    inherit (types)
      severity
      nonempty
      coordinate
      point
      range
      location
      presentation
      checked
      outcome
      ;
  };
}
