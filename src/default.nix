{ lib, fx }:
let
  types = import ./types.nix { inherit fx; };
  path = import ./path.nix { inherit lib types; };
  diagnostic = import ./diagnostics.nix {
    inherit fx types path;
  };
  render = import ./render.nix { inherit lib diagnostic path; };
  report = import ./report.nix {
    inherit
      lib
      fx
      diagnostic
      render
      types
      ;
  };
in
{
  diagnostic = { inherit (diagnostic) make factory types; };
  path = {
    inherit (path)
      normalize
      render
      field
      index
      variant
      ;
  };
  inherit render;
  report = {
    inherit (report)
      emit
      fail
      withContext
      run
      handlers
      ;
  };
  validation = import ./validation.nix {
    inherit
      fx
      diagnostic
      report
      path
      ;
  };
  inspect = import ./inspect.nix { inherit lib types; };
  suggest = import ./suggestions.nix { inherit lib; };
  nix.withErrorContext =
    message: value:
    if !builtins.isString message then
      throw "krisis: error context must be a string"
    else
      builtins.addErrorContext message value;
}
