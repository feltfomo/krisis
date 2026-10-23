{ lib, fx }:
let
  source = import ../nix/qualified-source.nix;
  shipped = import source { inherit lib; };
  public = (import ../flake.nix).outputs {
    flake-parts.lib.mkFlake = _: definition: { lib = definition.flake.lib; };
    nixpkgs.lib = throw "public constructor demanded repository source filtering";
  };
  k = public.lib.krisis { inherit lib fx; };
  poison = throw "public constructor forced opaque payload";
  report = k.report.run { } (
    fx.bind
      (k.report.emit {
        code = "first";
        severity = "error";
        message = "first diagnostic";
        context = poison;
      })
      (
        _:
        fx.bind
          (k.report.emit {
            code = "second";
            severity = "warning";
            message = "second diagnostic";
            context = poison;
          })
          (
            _:
            fx.pure {
              value = 7;
              opaque = poison;
            }
          )
      )
  );
  success = k.report.run { } (
    fx.pure {
      value = 7;
      opaque = poison;
    }
  );
  collect =
    effects: type: value:
    (effects.handle {
      state = [ ];
      handlers = {
        inherit (effects.effects.typecheck.collecting) deriveBounce;
        typeCheck = { param, state }: {
          resume = null;
          state = state ++ [ param.reason ];
        };
      };
    } (type.validate value)).state;
in
{
  test-public-constructor-report = {
    expr = {
      codes = map (d: d.code) report.diagnostics;
      inherit (report.summary) total hasErrors;
      outcome = report.outcome._con;
      failureHasValue = report.outcome ? value;
      inherit (fx.state.forceThunk success.outcome.value) value;
    };
    expected = {
      codes = [
        "first"
        "second"
      ];
      total = 2;
      hasErrors = true;
      outcome = "Failure";
      failureHasValue = false;
      value = 7;
    };
  };
  test-public-constructor-supplied-lib = {
    expr =
      (public.lib.krisis {
        inherit fx;
        lib = lib // {
          concatMapStrings = _: _: "supplied-lib";
        };
      }).path.render
        [ ];
    expected = "$supplied-lib";
  };
  test-public-constructor-supplied-fx = {
    expr =
      (public.lib.krisis {
        inherit lib;
        fx = fx // {
          handle = _: _: "supplied-fx";
        };
      }).report.run
        { }
        (fx.pure null);
    expected = "supplied-fx";
  };
  test-source-is-plain-path = {
    expr = builtins.typeOf source;
    expected = "path";
  };
  test-shipped-correction = {
    expr = collect shipped (shipped.types.Record { known = shipped.types.Int; }) {
      known = 1;
      unknown = throw "extra value forced";
    };
    expected = [ "extra-field" ];
  };
  test-qualified-instance-correction = {
    expr = collect fx (fx.types.Record { known = fx.types.Int; }) {
      known = 1;
      unknown = throw "extra value forced";
    };
    expected = [ "extra-field" ];
  };
}
