# Getting started

This guide builds a consumer that emits a warning, renders a report, and then
checks configuration before using it. Use Nix 2.35.1 with `nix-command`, `flakes`,
and `pipe-operators` enabled. The maintained checks qualify that evaluator;
other evaluators aren't established by the host's use of Lix. Repository
contributors can use the [pinned development shell](development.md).

## Consumer setup

Create these two files in your consumer project. In `flake.nix`:

```nix
{
  inputs = {
    krisis.url = "github:feltfomo/krisis";
    nixpkgs.follows = "krisis/nixpkgs";
  };

  outputs = inputs:
    let
      lib = inputs.nixpkgs.lib;
      fx = import inputs.krisis.lib.qualifiedNixEffectsSource {
        inherit lib;
      };
    in {
      demo = import ./diagnostics.nix {
        inherit lib fx;
        k = inputs.krisis.lib.krisis { inherit lib fx; };
      };
    };
}
```

`lib.qualifiedNixEffectsSource` is a plain corrected source tree. Importing it
requires neither import-from-derivation nor a native patch builder. The export is
independent of the consumer's system. Let Nix create a lockfile for your consumer
so later evaluations use the same inputs. If the consumer is in Git, include its
new files before evaluating its flake.

The consumer owns `lib`. This example follows Krisis's nixpkgs input to use the
same revision. Import the source with that `lib`, then pass the same `fx` to Krisis
and your computations. The existing `packages.<system>.qualified-nix-effects`
package supplies identical source bytes after build-time parity verification.
Krisis doesn't fetch an effect instance or re-export nix-effects.

In `diagnostics.nix`:

```nix
{ lib, fx, k }:
let
  report = k.report.run {} (fx.bind
    (k.report.emit {
      code = "service/default-port";
      severity = "warning";
      message = "using port 8080";
    })
    (_: fx.pure 8080));
in {
  text = k.render.plainReport report;
  status = report.outcome._con;
  value = fx.state.forceThunk report.outcome.value;
}
```

Evaluate it with:

```fish
nix --extra-experimental-features 'nix-command flakes pipe-operators' eval --raw .#demo.text
nix --extra-experimental-features 'nix-command flakes pipe-operators' eval --json .#demo.status
nix --extra-experimental-features 'nix-command flakes pipe-operators' eval --json .#demo.value
```

The text is:

```text
warning [service/default-port] using port 8080
```

The status is `"Success"` and the value is `8080`. `report.emit` resumes with
`null`; `fx.bind` sequences the next computation, and `fx.pure` supplies its result.
A warning doesn't fail this report. An emitted error would mark the report as
failed while collecting continued; `report.fail` also stops its continuation.

A successful report stores its result in a `Thunk`, nix-effects' carrier for values
that must stay lazy while interpreter state is deeply forced. Use
`fx.state.forceThunk` only after inspecting the outcome constructor. `Failure`
has no `value` field. Rendering a report never recovers this application value.
See [Outcome and Checked](api.md#checked-and-outcome) for the two result boundaries.

## Check input before using it

Replace `diagnostics.nix` with this complete expression:

```nix
{ lib, fx, k }:
let
  T = k.validation.types;
  port = T.refined "Port" T.Int (n: n > 0 && n < 65536);
  check = k.validation.check {
    type = T.Record {
      ports = T.ListOf port;
      payload = T.Any;
    };
    code = "service/shape";
    location.source = "caller-supplied.nix";
  };
  report = k.report.run {} (k.validation.andThen
    (value: fx.pure value.ports)
    (check {
      ports = [ 8080 (-1) ];
      payload = throw "opaque application data";
    }));
in {
  text = k.render.plainReport report;
  status = report.outcome._con;
  count = report.summary.total;
}
```

Evaluating `demo.text` now produces:

```text
error [service/shape] caller-supplied.nix $.ports[1]: $.ports[1]: predicate-failed; expected Port; got int
```

`demo.status` is `"Failure"` and `demo.count` is `1`. The source string identifies
caller-supplied provenance; Krisis doesn't read that file. The first path locates
the diagnostic, and the message also describes the validation path.

`T.Record` requires its declared fields and rejects extras. `T.ListOf port` checks
each element; `T.Any` leaves `payload` opaque, so its throw isn't evaluated here.
`validation.check` returns a computation of `Checked`. `validation.andThen` unwraps
only `Valid` and passes its value to the callback. Invalid input skips dependent
work, so the callback doesn't read the invalid ports. Predicate or callback throws
remain evaluation exceptions, rather than becoming input diagnostics.

For valid ports, the callback above returns a plain list. That list is the successful
report value. If you run `check` alone, the successful report value is instead a
`Checked` record with its own thunked value. These represent different contracts.

## Accumulate independent checks

Independent checks can all run even when one fails. Replace `diagnostics.nix` with:

```nix
{ lib, fx, k }:
let
  T = k.validation.types;
  check = code: type: value:
    k.validation.check { inherit code type; } value;
  checked = k.validation.all [
    (check "port" T.Int false)
    (check "name" T.String 1)
  ];
  report = k.report.run {} (k.validation.andThen
    (_: throw "dependent work must be skipped")
    checked);
in {
  text = k.render.plainReport report;
  codes = map (d: d.code) report.diagnostics;
  status = report.outcome._con;
}
```

`demo.codes` is `["port","name"]`, in check order, and `demo.status` is
`"Failure"`. Both checks run and the dependent throw is skipped. On success,
`validation.all` returns `Valid` with a thunked list of values in the same order.
This is applicative accumulation: checks don't need one another's results.
Use `andThen` when the next computation needs valid input.

## Continue with a specific task

- [Validation constructors](api.md#validationtypes) list supported signatures, including variants and nullable fields.
- [Report policy](api.md#policy-and-visibility) controls warning promotion and display filtering without losing failures.
- [Rendering](api.md#render) covers text, JSON, and custom formatters.
- [Nix module integration](api.md#nixmodule) explains assertion declarations and consumption.
- [Executable examples](README.md#executable-examples) cover locations, composition, and larger interpreters.

For a local checkout, `import ./src { inherit lib fx; }` initializes the same
library as the flake's `lib.krisis`. Keep using the shipped qualified dependency.
