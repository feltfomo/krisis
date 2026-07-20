{ lib }:
let
  isDerivation = value: builtins.isAttrs value && (value.type or null) == "derivation";
in
{
  safeRender =
    value:
    if isDerivation value then
      "<derivation ${value.name or "?"}>"
    else if builtins.isFunction value then
      "<function>"
    else
      let
        rendered = builtins.tryEval (builtins.toJSON value);
      in
      if rendered.success then rendered.value else "<unrenderable value>";

  safeShape =
    value:
    if isDerivation value then
      "<derivation ${value.name or "?"}>"
    else if builtins.isAttrs value then
      "{ ${lib.concatStringsSep ", " (builtins.sort (a: b: a < b) (builtins.attrNames value))} }"
    else
      "<${builtins.typeOf value}>";
}
