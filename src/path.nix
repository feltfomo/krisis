{
  lib,
  types,
}:
let
  position =
    raw:
    let
      args = types.closed "upstream position" [
        "_tag"
        "tag"
        "segment"
        "intent"
        "rule"
        "name"
        "idx"
        "layer"
      ] raw;
      normalized = {
        rule = null;
        name = null;
        idx = null;
        layer = null;
      }
      // args;
    in
    builtins.seq args (types.expect "upstream position" types.position normalized);
  segment =
    raw:
    let
      args = types.closed "path segment" [ "field" "index" "variant" "upstream" ] raw;
    in
    if builtins.attrNames args == [ "upstream" ] then
      let
        p = position args.upstream;
      in
      builtins.seq p { upstream = p; }
    else
      types.expect "path segment" types.segment args;
  normalize =
    value:
    if !builtins.isList value then
      throw "krisis: path must be a list"
    else
      let
        normalized = map segment value;
        checked = builtins.foldl' (unit: part: builtins.seq part unit) null normalized;
      in
      builtins.seq checked normalized;
  fromUpstream =
    raw:
    let
      p = position raw;
    in
    if p.tag == "Field" then
      { field = p.name; }
    else if p.tag == "Elem" then
      { index = p.idx; }
    else if p.tag == "Tag" then
      { variant = p.name; }
    else
      { upstream = p; };
  projectPosition = p: {
    inherit (p)
      _tag
      tag
      segment
      intent
      rule
      name
      idx
      layer
      ;
  };
  render =
    value:
    normalize value
    |> (
      parts:
      "$"
      + lib.concatMapStrings (
        part:
        if part ? field then
          ".${lib.strings.escapeNixIdentifier part.field}"
        else if part ? index then
          "[${toString part.index}]"
        else if part ? variant then
          "#${builtins.toJSON part.variant}"
        else
          "<${builtins.toJSON (projectPosition part.upstream)}>"
      ) parts
    );
in
{
  inherit
    normalize
    render
    fromUpstream
    ;
  field = name: segment { field = name; };
  index = n: segment { index = n; };
  variant = tag: segment { variant = tag; };
}
