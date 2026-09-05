{ lib }:
let
  editDistance = lib.strings.levenshtein;

  suggestWith =
    {
      maxDistance ? null,
    }:
    input: candidates:
    if !builtins.isString input then
      throw "krisis: suggestion input must be a string"
    else if !builtins.isList candidates || !lib.all builtins.isString candidates then
      throw "krisis: suggestion candidates must be a list of strings"
    else if maxDistance != null && (!builtins.isInt maxDistance || maxDistance < 0) then
      throw "krisis: suggestion distance must be a non-negative integer or null"
    else
      let
        threshold =
          if maxDistance != null then
            maxDistance
          else if builtins.stringLength input <= 4 then
            1
          else
            3;
        best = builtins.foldl' (
          current: candidate:
          if current != null && current.distance == 0 then
            current
          else
            let
              bound = if current == null then threshold else current.distance - 1;
            in
            if lib.strings.levenshteinAtMost bound input candidate then
              {
                name = candidate;
                distance = editDistance input candidate;
              }
            else
              current
        ) null candidates;
      in
      if best == null then null else best.name;

  suggest = suggestWith { };
in
{
  inherit editDistance suggest suggestWith;
}
