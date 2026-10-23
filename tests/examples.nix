{
  lib,
  fx,
  assertionsModule,
}:
let
  args = { inherit lib fx; };
  k = import ../src args;
  composition = import ../examples/composition.nix args;
  locations = import ../examples/locations.nix args;
  interpretation = import ../examples/interpretation.nix args;
  module = lib.evalModules {
    modules = [
      assertionsModule
      (import ../examples/module.nix args)
    ];
  };
in
{
  test-collected = {
    expr = (import ../examples/basic.nix args).summary.total;
    expected = 1;
  };
  test-independent = {
    expr = map (d: d.code) composition.independent.diagnostics;
    expected = [
      "port"
      "name"
    ];
  };
  test-dependent = {
    expr = composition.dependent.summary.total;
    expected = 1;
  };
  test-restored-locations = {
    expr = map (d: d.primary) locations.diagnostics;
    expected = [
      {
        label = null;
        source = "service.nix";
        path = [ ];
        range = null;
      }
      {
        label = "nested";
        source = "service.nix";
        path = [ ];
        range = null;
      }
      {
        label = null;
        source = "service.nix";
        path = [ ];
        range = null;
      }
    ];
  };
  test-custom-interpretation = {
    expr = {
      count = interpretation.state;
      observed = interpretation.value.observed;
      value = fx.state.forceThunk interpretation.value.report.outcome.value;
    };
    expected = {
      count = 1;
      observed = 1;
      value = 42;
    };
  };
  test-json = {
    expr = (builtins.fromJSON (import ../examples/json.nix args)).outcome;
    expected.status = "Success";
  };
  test-module = {
    expr = lib.asserts.checkAssertWarn module.config.assertions module.config.warnings "accepted";
    expected = "accepted";
  };
  test-custom-formatter = {
    expr = k.render.custom (p: "${p.code}: ${p.message}") {
      code = "example";
      message = "notice";
    };
    expected = "example: notice";
  };
}
