{ fx }:
let
  T = fx.types;
  H = T.hoas;
  nonempty = T.refined "NonemptyString" T.String (s: s != "");
  severity = T.refined "Severity" T.String (
    s:
    builtins.elem s [
      "error"
      "warning"
      "info"
    ]
  );
  natural = T.refined "Natural" T.Int (n: n >= 0);
  coordinate = T.refined "Coordinate" T.Int (n: n >= 1);
  point = T.Record {
    line = coordinate;
    column = coordinate;
  };
  range = T.refined "Range" (T.Record {
    start = point;
    end = point;
  }) (r: r.end.line > r.start.line || (r.end.line == r.start.line && r.end.column >= r.start.column));
  positionFields =
    T.refined "PositionFields"
      (T.Record {
        tag = nonempty;
        segment = nonempty;
        intent = nonempty;
        rule = T.Maybe T.String;
        name = T.Maybe T.String;
        idx = T.Maybe natural;
        layer = T.Maybe natural;
      })
      (
        p:
        if
          builtins.elem p.tag [
            "Field"
            "Tag"
            "Case"
          ]
        then
          p.name != null && p.idx == null && p.layer == null
        else if
          builtins.elem p.tag [
            "Elem"
            "Tuple"
          ]
        then
          p.idx != null && p.name == null && p.layer == null
        else if p.tag == "DConLayer" then
          p.layer != null && p.name == null && p.idx == null
        else
          p.name == null && p.idx == null && p.layer == null
      );
  # keep the Position marker outside Record's constructor discriminator lookup
  position = T.refined "Position" T.Attrs (
    p:
    builtins.isString (p._tag or null)
    && p._tag == "Position"
    && positionFields.check (removeAttrs p [ "_tag" ])
  );
  segment = T.refined "PathSegment" T.Attrs (
    v:
    let
      names = builtins.attrNames v;
    in
    if names == [ "field" ] then
      T.String.check v.field
    else if names == [ "index" ] then
      natural.check v.index
    else if names == [ "variant" ] then
      T.String.check v.variant
    else
      names == [ "upstream" ] && position.check v.upstream
  );
  envelope = T.Record {
    inherit severity;
    code = nonempty;
  };
  location =
    T.refined "Location"
      (T.Record {
        label = T.Maybe T.String;
        source = T.Maybe T.String;
        path = T.ListOf segment;
        range = T.Maybe range;
      })
      (
        l: (l.label != null || l.source != null || l.path != [ ]) && (l.range == null || l.source != null)
      );
  related = T.Record {
    inherit location;
    message = T.Maybe T.String;
  };
  presentation = T.Record {
    inherit severity;
    code = nonempty;
    message = T.String;
    primary = T.Maybe location;
    related = T.ListOf related;
    notes = T.ListOf T.String;
    help = T.Maybe T.String;
  };
  checked = H.datatype "Checked" [
    (H.con "Valid" [ (H.field "value" (H.thunk H.any)) ])
    (H.con "Invalid" [ ])
  ];
  outcome = H.datatype "Outcome" [
    (H.con "Success" [ (H.field "value" (H.thunk H.any)) ])
    (H.con "Failure" [ ])
  ];
  expect =
    name: type: value:
    builtins.seq value (if type.check value then value else throw "krisis: invalid ${name}");
  closed =
    name: fields: value:
    if !builtins.isAttrs value then
      throw "krisis: ${name} must be an attribute set"
    else if builtins.any (field: !(builtins.elem field fields)) (builtins.attrNames value) then
      throw "krisis: unknown ${name} field"
    else
      value;
in
{
  inherit
    nonempty
    severity
    natural
    coordinate
    point
    range
    segment
    position
    envelope
    location
    related
    presentation
    checked
    outcome
    expect
    closed
    ;
}
