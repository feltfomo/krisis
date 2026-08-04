{ lib }:
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
    throw "krisis: ${field} must be ${expected}; got ${builtins.typeOf value}";

  validateOptions =
    {
      options,
      allowed,
      bounds ? [ ],
      strings ? [ ],
    }:
    if !builtins.isAttrs options then
      invalid "render options" "an attribute set" options
    else
      let
        unknown = builtins.filter (name: !(builtins.elem name allowed)) (builtins.attrNames options);
        badBound = lib.findFirst (
          name: options ? ${name} && (!builtins.isInt options.${name} || options.${name} < 0)
        ) null bounds;
        badString = lib.findFirst (
          name: options ? ${name} && !builtins.isString options.${name}
        ) null strings;
      in
      if unknown != [ ] then
        throw "krisis: unknown render options ${lib.concatStringsSep ", " unknown}"
      else if badBound != null then
        invalid "render option '${badBound}'" "a non-negative integer" options.${badBound}
      else if badString != null then
        invalid "render option '${badString}'" "a string" options.${badString}
      else
        true;

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
      attempted = builtins.tryEval (
        let
          count = builtins.length values;
          shown = lib.take config.maxListItems values;
        in
        if builtins.all (value: builtins.elem (builtins.typeOf value) scalarTypes) shown then
          {
            rendered = builtins.toJSON (map (normalizeScalar config.maxStringLength) shown);
            omitted = count - builtins.length shown;
          }
        else
          null
      );
    in
    if !attempted.success || attempted.value == null then
      config.fallback
    else
      attempted.value.rendered
      + lib.optionalString (attempted.value.omitted > 0) " (+${toString attempted.value.omitted} more)";

  safeRenderWith =
    options: value:
    let
      config = {
        maxStringLength = options.maxStringLength or 256;
        maxListItems = options.maxListItems or 32;
        fallback = options.fallback or "<unrenderable value>";
      };
      valid = validateOptions {
        inherit options;
        allowed = [
          "maxStringLength"
          "maxListItems"
          "fallback"
        ];
        bounds = [
          "maxStringLength"
          "maxListItems"
        ];
        strings = [ "fallback" ];
      };
    in
    builtins.seq valid (
      if isDerivation value then
        "<derivation ${truncate config.maxStringLength (derivationName value)}>"
      else if builtins.isFunction value then
        "<function>"
      else if builtins.isAttrs value then
        config.fallback
      else if builtins.isList value then
        renderScalarList config value
      else
        let
          rendered = builtins.tryEval (renderScalar config.maxStringLength value);
        in
        if rendered.success && rendered.value != null then rendered.value else config.fallback
    );

  safeShapeWith =
    options: value:
    let
      maxAttrs = options.maxAttrs or 32;
      valid = validateOptions {
        inherit options;
        allowed = [ "maxAttrs" ];
        bounds = [ "maxAttrs" ];
      };
      names = if builtins.isAttrs value then builtins.attrNames value else [ ];
      shown = lib.take maxAttrs names;
      omitted = builtins.length names - builtins.length shown;
      suffix = lib.optionalString (omitted > 0) ", … (+${toString omitted})";
    in
    builtins.seq valid (
      if isDerivation value then
        "<derivation ${derivationName value}>"
      else if builtins.isAttrs value then
        "{ ${lib.concatStringsSep ", " shown}${suffix} }"
      else
        "<${builtins.typeOf value}>"
    );

  safeIdentity =
    args@{
      value,
      label ? null,
      source ? null,
      noun ? "value",
    }:
    let
      unknown = builtins.filter (
        name:
        !(builtins.elem name [
          "value"
          "label"
          "source"
          "noun"
        ])
      ) (builtins.attrNames args);
    in
    if unknown != [ ] then
      throw "krisis: safeIdentity received unknown fields ${lib.concatStringsSep ", " unknown}"
    else if label != null && !builtins.isString label then
      invalid "safeIdentity label" "a string or null" label
    else if source != null && !builtins.isString source then
      invalid "safeIdentity source" "a string or null" source
    else if !builtins.isString noun then
      invalid "safeIdentity noun" "a string" noun
    else if label != null then
      "${noun} '${label}'"
    else if source != null then
      "${noun} at ${source}"
    else
      "${noun} ${safeShapeWith { } value}";
in
{
  safeRender = safeRenderWith { };
  safeShape = safeShapeWith { };
  inherit
    safeRenderWith
    safeShapeWith
    safeIdentity
    ;
}
