{
  lib,
  identity,
  validation,
  schema,
}:
let
  scalarTypes = [
    "bool"
    "float"
    "int"
    "null"
    "path"
    "string"
  ];
  invalid =
    field: expected: value:
    "${field} must be ${expected}; got ${builtins.typeOf value}";
  failKrisis = diagnostics: throw "krisis: ${lib.concatStringsSep "; " diagnostics}";
  finish = validation.finish failKrisis;

  boundField = name: default: {
    inherit default;
    validate = value: builtins.isInt value && value >= 0;
    onInvalid = _record: value: invalid "render option '${name}'" "a non-negative integer" value;
  };

  renderOptions = schema.compile {
    onRecord = value: invalid "render options" "an attribute set" value;
    onUnknown = name: _value: "unknown render option '${name}'";
    order = [
      "maxStringLength"
      "maxListItems"
      "fallback"
    ];
    fields = {
      maxStringLength = boundField "maxStringLength" 256;
      maxListItems = boundField "maxListItems" 32;
      fallback = {
        default = "<unrenderable value>";
        validate = builtins.isString;
        onInvalid = _record: value: invalid "render option 'fallback'" "a string" value;
      };
    };
  };

  shapeOptions = schema.compile {
    onRecord = value: invalid "render options" "an attribute set" value;
    onUnknown = name: _value: "unknown render option '${name}'";
    order = [ "maxAttrs" ];
    fields.maxAttrs = boundField "maxAttrs" 32;
  };

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

  safeRenderWith =
    options: value:
    let
      config = finish (renderOptions options);
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

  safeShapeWith =
    options: value:
    let
      config = finish (shapeOptions options);
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

  nullableString = name: {
    default = null;
    validate = value: value == null || builtins.isString value;
    onInvalid = _record: value: invalid "safeIdentity ${name}" "a string or null" value;
  };

  identityArgs = schema.compile {
    onRecord = value: invalid "safeIdentity arguments" "an attribute set" value;
    onUnknown = name: _value: "safeIdentity does not accept field '${name}'";
    order = [
      "value"
      "label"
      "source"
      "noun"
    ];
    fields = {
      value = {
        required = true;
        onMissing = _record: "safeIdentity is missing required field 'value'";
      };
      label = nullableString "label";
      source = nullableString "source";
      noun = {
        default = "value";
        validate = builtins.isString;
        onInvalid = _record: value: invalid "safeIdentity noun" "a string" value;
      };
    };
  };

  safeIdentity =
    args:
    let
      config = finish (identityArgs args);
    in
    identity.render {
      identity = identity.mk { inherit (config) label source; };
      renderLabel = selected: "${config.noun} '${selected}'";
      renderSource = selected: "${config.noun} at ${selected}";
      renderPath = selected: "${config.noun} at ${lib.concatStringsSep "." selected}";
      fallback = "${config.noun} ${safeShapeWith { } config.value}";
    };
in
{
  safeRender = safeRenderWith { };
  safeShape = safeShapeWith { };
  inherit safeRenderWith safeShapeWith safeIdentity;
}
