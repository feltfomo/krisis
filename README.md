# Krisis

Krisis helps Nix configuration libraries report several input problems in one
pass. Give diagnostics stable codes, structured paths, and caller-supplied source
locations. Collect them into a report, render them as text or JSON, or use the
report to supply Nix module assertions and warnings.

A diagnostic computation describes what to report. The interpreter chooses whether
to collect problems or stop at the first error. For example, with `k` and `fx`
initialized as in [Getting started](docs/getting-started.md#consumer-setup):

```nix
let
  report = k.report.run {} (fx.bind
    (k.report.emit {
      code = "service/default-port";
      severity = "warning";
      message = "using port 8080";
    })
    (_: fx.pure 8080));
in k.render.plainReport report
```

Rendered output:

```text
warning [service/default-port] using port 8080
```

The warning-only report succeeds. Its successful value is protected by a thunk
carrier; `fx.state.forceThunk report.outcome.value` recovers `8080`. Diagnostics can
carry opaque context without rendering or serializing it.

Use Nix 2.35.1 with `pipe-operators`, the qualified evaluator and feature used by
the maintained checks. Import the shipped corrected nix-effects source with your
own `lib`, and share the resulting `fx` instance with Krisis and your computations.
The [complete setup and first workflow](docs/getting-started.md) introduces every
input and shows validation and failure handling.

- [API reference](docs/api.md) for operation signatures and data contracts.
- [Examples and documentation index](docs/README.md) for worked expressions.
- [Development](docs/development.md) for contributor checks.
- [Qualification](docs/qualification.md) for dependency and evaluation constraints.
