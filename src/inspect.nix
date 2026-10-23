{ lib, types }:
let
  scalarTypes = [
    "bool"
    "float"
    "int"
    "null"
    "path"
    "string"
  ];
  options =
    allowed: defaults: raw:
    let
      args = types.closed "inspection options" allowed raw;
      config = defaults // args;
      valid = builtins.all (
        name:
        if name == "fallback" then
          builtins.isString config.${name}
        else
          builtins.isInt config.${name} && config.${name} >= 0
      ) allowed;
    in
    if valid then config else throw "krisis: invalid inspection options";
  renderOptions = options [ "maxStringLength" "maxListItems" "fallback" ] {
    maxStringLength = 256;
    maxListItems = 32;
    fallback = "<unrenderable value>";
  };
  shapeOptions = options [ "maxAttrs" ] { maxAttrs = 32; };

  isDerivation =
    value:
    if !builtins.isAttrs value || !(value ? type) then
      false
    else
      let
        attempted = builtins.tryEval value.type;
      in
      attempted.success && builtins.isString attempted.value && attempted.value == "derivation";

  derivationName =
    value:
    let
      attempted = if value ? name then builtins.tryEval value.name else { success = false; };
    in
    if attempted.success && builtins.isString attempted.value then attempted.value else "?";

  truncate =
    limit: value:
    if builtins.stringLength value <= limit then value else "${builtins.substring 0 limit value}…";

  normalizeScalar =
    maxStringLength: value:
    if builtins.isPath value then
      truncate maxStringLength (builtins.unsafeDiscardStringContext (toString value))
    else if builtins.isString value then
      truncate maxStringLength value
    else
      value;

  renderScalar =
    maxStringLength: value:
    if builtins.elem (builtins.typeOf value) scalarTypes then
      builtins.toJSON (normalizeScalar maxStringLength value)
    else
      null;

  renderScalarList =
    config: values:
    let
      shown = lib.take config.maxListItems values;
      omitted = builtins.length values - builtins.length shown;
    in
    if builtins.all (value: builtins.elem (builtins.typeOf value) scalarTypes) shown then
      builtins.toJSON (map (normalizeScalar config.maxStringLength) shown)
      + lib.optionalString (omitted > 0) " (+${toString omitted} more)"
    else
      config.fallback;

  attempt =
    fallback: rendered:
    let
      result = builtins.tryEval rendered;
    in
    if result.success && result.value != null then result.value else fallback;

  renderValue =
    options: value:
    let
      config = renderOptions options;
    in
    # malformed options must not be swallowed by the rendering fallback
    builtins.seq config (
      attempt config.fallback (
        if isDerivation value then
          "<derivation ${truncate config.maxStringLength (derivationName value)}>"
        else if builtins.isFunction value then
          "<function>"
        else if builtins.isAttrs value then
          config.fallback
        else if builtins.isList value then
          renderScalarList config value
        else
          renderScalar config.maxStringLength value
      )
    );

  renderShape =
    options: value:
    let
      config = shapeOptions options;
      names = if builtins.isAttrs value then builtins.attrNames value else [ ];
      shown = lib.take config.maxAttrs names;
      omitted = builtins.length names - builtins.length shown;
      suffix = lib.optionalString (omitted > 0) ", … (+${toString omitted})";
    in
    builtins.seq config (
      attempt "<unrenderable value>" (
        if isDerivation value then
          "<derivation ${derivationName value}>"
        else if builtins.isAttrs value then
          "{ ${lib.concatStringsSep ", " shown}${suffix} }"
        else
          "<${builtins.typeOf value}>"
      )
    );

  identify =
    raw:
    let
      args = types.closed "identity" [ "value" "label" "source" "noun" ] raw;
      config = {
        label = null;
        source = null;
        noun = "value";
      }
      // args;
      valid =
        args ? value
        && builtins.isString config.noun
        && (config.label == null || builtins.isString config.label)
        && (config.source == null || builtins.isString config.source);
    in
    if !valid then
      throw "krisis: invalid identity options"
    else if config.label != null then
      "${config.noun} '${config.label}'"
    else if config.source != null then
      "${config.noun} at ${config.source}"
    else
      "${config.noun} ${renderShape { } config.value}";
in
{
  value = renderValue;
  shape = renderShape;
  identity = identify;
}
