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

  normalizeScalar =
    value:
    if builtins.isPath value then builtins.unsafeDiscardStringContext (toString value) else value;

  renderScalar =
    value:
    if builtins.elem (builtins.typeOf value) scalarTypes then
      builtins.toJSON (normalizeScalar value)
    else
      null;

  renderScalarList =
    values:
    let
      attempted = builtins.tryEval (
        if builtins.all (value: builtins.elem (builtins.typeOf value) scalarTypes) values then
          builtins.toJSON (map normalizeScalar values)
        else
          null
      );
    in
    if attempted.success && attempted.value != null then attempted.value else "<unrenderable value>";
in
{
  safeRender =
    value:
    if isDerivation value then
      "<derivation ${derivationName value}>"
    else if builtins.isFunction value then
      "<function>"
    else if builtins.isAttrs value then
      "<unrenderable value>"
    else if builtins.isList value then
      renderScalarList value
    else
      let
        rendered = builtins.tryEval (renderScalar value);
      in
      if rendered.success && rendered.value != null then rendered.value else "<unrenderable value>";

  safeShape =
    value:
    if isDerivation value then
      "<derivation ${derivationName value}>"
    else if builtins.isAttrs value then
      "{ ${lib.concatStringsSep ", " (builtins.attrNames value)} }"
    else
      "<${builtins.typeOf value}>";
}
