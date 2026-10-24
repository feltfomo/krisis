{
  fx,
  diagnostic,
  report,
  path,
}:
let
  inherit (fx.state) mkThunk forceThunk;
  T = fx.types;
  # the constructor owner closes over qualified upstream types, never caller verifiers
  owned = type: { krisisValidation = continuation: continuation type; };
  require =
    candidate:
    if
      builtins.isAttrs candidate
      && builtins.attrNames candidate == [ "krisisValidation" ]
      && builtins.isFunction candidate.krisisValidation
    then
      candidate.krisisValidation (type: type)
    else
      throw "krisis: unsupported validation type; use validation.types";
  unary =
    constructor: candidate:
    let
      inner = require candidate;
    in
    builtins.seq inner (owned (constructor inner));
  fields =
    constructor: candidates:
    let
      children = builtins.mapAttrs (_: require) candidates;
      admittedChildren = builtins.foldl' (unit: child: builtins.seq child unit) null (
        builtins.attrValues children
      );
    in
    builtins.seq admittedChildren (owned (constructor children));
  admitted =
    (builtins.mapAttrs (_: owned) {
      inherit (T)
        String
        Int
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
    // {
      Record = fields T.Record;
      ListOf = unary T.ListOf;
      Maybe = unary T.Maybe;
      Variant = fields T.Variant;
      Either =
        left: right:
        let
          l = require left;
          r = require right;
        in
        builtins.seq l (builtins.seq r (owned (T.Either l r)));
      refine =
        base: predicate:
        let
          inner = require base;
        in
        builtins.seq inner (owned (T.refine inner predicate));
      refined =
        name: base: predicate:
        let
          inner = require base;
        in
        builtins.seq inner (owned (T.refined name inner predicate));
    };
  check =
    {
      type,
      code,
      location ? null,
    }:
    let
      upstream = require type;
      template = diagnostic.make {
        inherit code;
        message = "";
      };
      checkedLocation = if location == null then null else diagnostic.location location;
    in
    value:
    let
      checked =
        fx.effects.scope.runWith
          {
            state = false;
            handlers = {
              inherit (fx.effects.typecheck.collecting) deriveBounce;
              typeCheck =
                { param, ... }:
                let
                  blame = map path.fromUpstream param.path;
                  reason = param.reason or "shape-mismatch";
                  actual = builtins.addErrorContext "krisis: while checking ${code}" (builtins.typeOf param.value);
                  located = (if checkedLocation == null then { } else checkedLocation) // {
                    path = (if checkedLocation == null then [ ] else checkedLocation.path) ++ blame;
                  };
                  d = diagnostic.make {
                    inherit code;
                    message = "${path.render located.path}: ${reason}; expected ${param.type.name}; got ${actual}";
                    primary = if located.path == [ ] && checkedLocation == null then null else located;
                    context.validation = {
                      path = blame;
                      inherit reason actual;
                      expected = param.type.name;
                    };
                  };
                in
                # demand only the failed value's outer shape, preserving thrown inputs
                builtins.seq actual {
                  state = true;
                  resume = fx.map (_: null) (report.emit d);
                };
            };
          }
          (
            fx.map mkThunk (builtins.addErrorContext "krisis: while checking ${code}" (upstream.validate value))
          );
    in
    builtins.seq upstream (
      builtins.seq template (
        fx.map (
          result:
          if result.state then
            { _con = "Invalid"; }
          else
            {
              _con = "Valid";
              inherit (result) value;
            }
        ) checked
      )
    );
  andThen =
    f: computation:
    fx.bind computation (
      checked:
      if checked._con == "Valid" then
        builtins.addErrorContext "krisis: while evaluating dependent validation" (
          f (forceThunk checked.value)
        )
      else
        fx.pure { _con = "Invalid"; }
    );
  all =
    checks:
    let
      step =
        acc: computation:
        fx.bind acc (
          previous:
          fx.bind computation (
            current:
            let
              previousNode = forceThunk previous.values;
              count = previous.count + 1;
              invalid = previous.invalid || current._con == "Invalid";
              next = builtins.deepSeq { inherit count invalid; } (
                builtins.seq previousNode {
                  inherit count invalid;
                  values = mkThunk {
                    previous = previousNode;
                    value = if current._con == "Valid" then current.value else null;
                  };
                }
              );
              # pure computations bypass interpreter state forcing, so settle bookkeeping here
            in
            builtins.seq next (fx.pure next)
          )
        );
      gathered = builtins.foldl' step (fx.pure {
        invalid = false;
        values = mkThunk null;
        count = 0;
      }) checks;
    in
    fx.map (
      result:
      if result.invalid then
        { _con = "Invalid"; }
      else
        {
          _con = "Valid";
          value = mkThunk (
            import ./spine.nix {
              inherit (result) count;
              head = forceThunk result.values;
              project = node: forceThunk node.value;
            }
          );
        }
    ) gathered;
in
{
  inherit check all andThen;
  types = admitted;
}
