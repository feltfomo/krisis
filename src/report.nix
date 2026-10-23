{
  lib,
  fx,
  diagnostic,
  render,
  types,
}:
let
  inherit (fx.state) mkThunk forceThunk;
  ask = fx.send "krisis.context" null;
  emptyDefaults = diagnostic.defaults { };
  withContext =
    raw: computation:
    let
      checked = diagnostic.defaults raw;
    in
    builtins.seq checked (
      fx.bind ask (
        parent:
        let
          env = diagnostic.mergeDefaults (forceThunk parent) raw;
        in
        fx.effects.scope.provide {
          "krisis.context" = { state, ... }: {
            inherit state;
            resume = mkThunk env;
          };
        } computation
      )
    );
  operation =
    name: raw:
    let
      d = diagnostic.make raw;
    in
    builtins.seq d (
      fx.bind ask (
        environment: fx.send name (mkThunk (diagnostic.applyDefaults (forceThunk environment) raw))
      )
    );
  policy =
    raw:
    let
      args = types.closed "policy" [ "warningsAsErrors" "minimumSeverity" "suppressCodes" ] raw;
      p = {
        warningsAsErrors = false;
        minimumSeverity = "info";
        suppressCodes = [ ];
      }
      // args;
    in
    if
      !builtins.isBool p.warningsAsErrors
      || !(types.severity.check p.minimumSeverity)
      || !(fx.types.ListOf fx.types.String).check p.suppressCodes
    then
      throw "krisis: invalid report policy"
    else
      p;
  rank = {
    info = 0;
    warning = 1;
    error = 2;
  };
  decide =
    p: d:
    let
      effectiveSeverity = if p.warningsAsErrors && d.severity == "warning" then "error" else d.severity;
    in
    {
      inherit effectiveSeverity;
      originalSeverity = d.severity;
      suppressed = builtins.elem d.code p.suppressCodes;
      belowThreshold = rank.${effectiveSeverity} < rank.${p.minimumSeverity};
      visible =
        !(builtins.elem d.code p.suppressCodes) && rank.${effectiveSeverity} >= rank.${p.minimumSeverity};
    };
  initialState = {
    head = mkThunk null;
    count = 0;
    failed = false;
  };
  record =
    p: strict: formatter: explicit:
    { param, state }:
    let
      d = diagnostic.make (forceThunk param);
      decision = decide p d;
      previous = forceThunk state.head;
      failed = explicit || decision.effectiveSeverity == "error";
      next = state // {
        count = state.count + 1;
        failed = state.failed || failed;
        # cache the previous pointer before closing over it, so each event owns one node
        head = builtins.seq previous (mkThunk {
          inherit previous;
          item = mkThunk {
            diagnostic = d;
            inherit decision;
          };
        });
      };
    in
    if strict && failed then
      throw (
        (if formatter == null then render.plain else render.custom formatter) (
          d // { severity = decision.effectiveSeverity; }
        )
      )
    else if explicit then
      {
        state = next;
        abort = {
          _con = "Failure";
        };
      }
    else
      {
        state = next;
        resume = null;
      };
  materialize =
    state:
    import ./spine.nix {
      inherit (state) count;
      head = forceThunk state.head;
      project = node: forceThunk node.item;
    };
  finish =
    result:
    let
      events = materialize result.state;
      bySeverity = lib.genAttrs [ "error" "warning" "info" ] (
        s: builtins.length (builtins.filter (e: e.decision.effectiveSeverity == s) events)
      );
      summary = {
        total = result.state.count;
        hasErrors = bySeverity.error > 0;
        inherit bySeverity;
        byCode = builtins.mapAttrs (_: builtins.length) (builtins.groupBy (e: e.diagnostic.code) events);
      };
    in
    {
      diagnostics = map (e: e.diagnostic) events;
      visibility = map (e: e.decision) events;
      inherit summary;
      outcome = if result.state.failed then { _con = "Failure"; } else result.value;
    };
  interpreter =
    strict:
    {
      policy ? { },
      handlers ? { },
      formatter ? null,
    }:
    let
      p = policyConfig policy;
      owned = {
        "krisis.context" = { state, ... }: {
          inherit state;
          resume = mkThunk emptyDefaults;
        };
        "krisis.emit" = record p strict formatter false;
        "krisis.fail" = record p strict formatter true;
      };
      collisions = lib.intersectLists (builtins.attrNames owned) (builtins.attrNames handlers);
    in
    builtins.seq p (
      if formatter != null && !builtins.isFunction formatter then
        throw "krisis: formatter must be a function"
      else if collisions != [ ] then
        throw "krisis: handler collision ${builtins.concatStringsSep ", " collisions}"
      else
        {
          state = initialState;
          handlers = handlers // owned;
          return =
            value: state:
            finish {
              inherit state;
              value = {
                _con = "Success";
                value = mkThunk value;
              };
            };
        }
    );
  policyConfig = policy;
  handlers = {
    collecting = interpreter false;
    strict = interpreter true;
  };
  run =
    {
      policy ? { },
      mode ? "collecting",
      handlers ? { },
      formatter ? null,
    }:
    computation:
    if
      !(builtins.elem mode [
        "collecting"
        "strict"
      ])
    then
      throw "krisis: invalid report mode"
    else
      fx.handle (interpreter (mode == "strict") { inherit policy handlers formatter; }) computation;
in
{
  inherit
    withContext
    run
    handlers
    ;
  emit = operation "krisis.emit";
  fail = operation "krisis.fail";
}
