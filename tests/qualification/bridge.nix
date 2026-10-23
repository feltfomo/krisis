{ fx, lib }:
let
  T = fx.types;
  admit = type: {
    _tag = "Qualified";
    inherit type;
  };
  require =
    candidate:
    if builtins.isAttrs candidate && (candidate._tag or null) == "Qualified" then
      candidate.type
    else
      throw "qualification: unsupported type";
  position =
    p:
    if p.tag == "Field" then
      { field = p.name; }
    else if p.tag == "Elem" then
      { index = p.idx; }
    else if p.tag == "Tag" then
      { variant = p.name; }
    else
      { upstream = p; };
  collect =
    computation:
    let
      result = fx.handle {
        state = [ ];
        handlers = {
          inherit (fx.effects.typecheck.collecting) deriveBounce;
          typeCheck = { param, state }: {
            resume = null;
            state = [
              {
                path = map position param.path;
                inherit (param) reason;
              }
            ]
            ++ state;
          };
        };
      } (fx.map fx.state.mkThunk computation);
    in
    {
      events = lib.reverseList result.state;
      inherit (result) value;
    };
in
{
  inherit collect;
  types = {
    inherit
      (builtins.mapAttrs (_: admit) {
        inherit (T)
          Int
          String
          Bool
          Float
          Attrs
          Path
          Function
          Unit
          Null
          Any
          ;
      })
      Int
      String
      Bool
      Float
      Attrs
      Path
      Function
      Unit
      Null
      Any
      ;
    Record = fields: admit (T.Record (builtins.mapAttrs (_: require) fields));
    ListOf = inner: admit (T.ListOf (require inner));
    Maybe = inner: admit (T.Maybe (require inner));
    Variant = branches: admit (T.Variant (builtins.mapAttrs (_: require) branches));
    Either = left: right: admit (T.Either (require left) (require right));
    refine = base: predicate: admit (T.refine (require base) predicate);
    refined =
      name: base: predicate:
      admit (T.refined name (require base) predicate);
  };
  check =
    candidate: value:
    let
      result = collect ((require candidate).validate value);
    in
    {
      inherit (result) events;
      checked =
        if result.events == [ ] then
          {
            _con = "Valid";
            inherit (result) value;
          }
        else
          { _con = "Invalid"; };
    };
  andThen =
    f: result:
    if result.checked._con == "Valid" then f (fx.state.forceThunk result.checked.value) else result;
  all =
    results:
    let
      events = lib.concatMap (result: result.events) results;
      invalid = lib.any (result: result.checked._con == "Invalid") results;
    in
    {
      inherit events;
      checked =
        if invalid then
          { _con = "Invalid"; }
        else
          {
            _con = "Valid";
            value = fx.state.mkThunk (map (result: fx.state.forceThunk result.checked.value) results);
          };
    };
}
