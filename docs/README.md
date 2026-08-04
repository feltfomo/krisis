# Krisis

Krisis is the shared diagnostic and safe-rendering library for `_lib` subsystems. It provides validated diagnostic records, caller-owned reporting policy, contextual evaluation, collection helpers, and bounded descriptions of values that may contain derivations, secrets, or throwing fields.

It is a maintainer API, not an aspect-authoring surface.

## Import

```nix
krisis = import ./modules/_lib/krisis { inherit lib; };
```

## Exports

| Function | Purpose |
| --- | --- |
| `mkDiagnostic` | Validate and construct one diagnostic record. |
| `mkDiagnosticFactory` | Bind default severity, code prefix, and primary location. |
| `qualifyCode` | Join a diagnostic namespace and local code. |
| `allowedSeverities` | Supported severity names. |
| `mkReporter` | Bind rendering and throwing policy once. |
| `renderDiagnostics` | Render a list with caller-provided formatting. |
| `throwDiagnostics` | Render and throw a list. |
| `collectDiagnostics` | Flatten ordered diagnostic groups. |
| `optionalDiagnostic` | Emit zero or one diagnostic from a condition. |
| `withErrorContext` | Add context while preserving the original Nix exception. |
| `safeRender` | Render bounded scalar information without traversing opaque payloads. |
| `safeRenderWith` | Configure string and list bounds and fallback text. |
| `safeShape` | Describe a type or shallow attrset shape. |
| `safeShapeWith` | Configure the number of exposed attr names. |
| `safeIdentity` | Prefer a label, then source, then shallow shape. |

## Diagnostic schema

```nix
krisis.mkDiagnostic {
  severity = "error";
  code = "program/directory-source-missing";
  message = "source does not exist in the flake";
  primary = {
    label = "directories[0]";
    source = "modules/aspects/example.nix";
  };
  secondaryLabels = [
    {
      label = "related declaration";
      message = "also contributes to this path";
    }
  ];
  notes = [ "git-backed flakes omit untracked files" ];
  help = "add a tracked file or remove the declaration";
  context.index = 0;
}
```

Required fields are:

- `severity`, one of `error`, `warning`, or `info`;
- non-empty `code`;
- string `message`.

`primary` accepts only optional string fields `label` and `source`.

Each `secondaryLabels` entry accepts optional string fields `label`, `source`, and `message`, and must identify a label or source. `notes` must be a list of strings and `help` must be a string. `context` remains caller-shaped and stays lazy.

Unknown fields and malformed optional data fail at construction rather than reaching a renderer.

## Diagnostic factories

Use a factory when one subsystem emits several related diagnostics:

```nix
problem = krisis.mkDiagnosticFactory {
  severity = "error";
  codePrefix = "furnish";
  primary.source = "modules/_lib/furnish/core.nix";
};

problem {
  code = "missing-executor";
  message = "no executor matched";
  primary.label = "kitty.conf";
}
```

The resulting code is `furnish/missing-executor`. Call-specific primary fields extend or override factory defaults.

## Reporters

A reporter binds one subsystem's visible formatting policy:

```nix
reporter = krisis.mkReporter {
  formatHeader = count: "example: ${toString count} error(s)";
  formatDiagnostic = diagnostic:
    "  - [${diagnostic.code}] ${diagnostic.message}";
  separator = "\n";
};

text = reporter.render diagnostics;
one = reporter.renderOne diagnostic;
value = reporter.checked diagnostics successfulValue;
```

Reporter methods are:

- `render` and `renderOne`;
- `fail` and `failOne`;
- `checked`, which returns a value only when the diagnostic list is empty.

`formatHeader` defaults to no header. Returning `null` omits it. `separator` defaults to a newline.

Aggregate independent diagnostics before throwing when the remaining input can be inspected safely. Do not run later dependent phases after an earlier phase is invalid merely to increase the count. Ownerships, for example, may aggregate several declaration diagnostics but must not run selection or merge after declaration validation fails.

## Contextual evaluation

Use `withErrorContext` around extension callbacks and other user-supplied evaluation boundaries:

```nix
krisis.withErrorContext
  "ownerships: while evaluating axis 'when' selector"
  (predicate ctx)
```

This uses `builtins.addErrorContext`, so the original exception remains visible. Do not replace callback failures with `tryEval`; Nix does not expose the original thrown message through `tryEval`.

Place the wrapper around the field that is actually forced. Wrapping a lazy record without forcing its failing field will not retain the context.

Context strings must not force labels, provenance, payloads, or other metadata that successful evaluation does not otherwise need. Prefer already-validated labels at an authoring boundary and shallow `safeShape` output at a generic engine boundary.

## Safe rendering

`safeRender` is for bounded value display in errors:

```nix
krisis.safeRender 42
# "42"

krisis.safeRender [ "a" "b" ]
# "[\"a\",\"b\"]"

krisis.safeRender (_: true)
# "<function>"
```

Behavior:

- strings, numbers, booleans, null, and paths render as JSON scalars;
- paths have string context discarded before rendering;
- lists render only when every inspected item is a recognized scalar;
- functions render as `<function>`;
- ordinary attrsets render as `<unrenderable value>`;
- derivations render as `<derivation NAME>`;
- a missing, throwing, or non-string derivation name becomes `?`;
- failed attempts return the configured fallback.

`safeRender` never recursively serializes arbitrary attrsets.

Use `safeRenderWith` to bound work and output:

```nix
krisis.safeRenderWith {
  maxStringLength = 128;
  maxListItems = 16;
  fallback = "<opaque>";
} value
```

Strings longer than the configured bound are truncated. Lists show at most the configured number of scalar items and report how many remain.

## Safe shape and identity

```nix
krisis.safeShape {
  services = { ... };
  packages = [ ... ];
}
# "{ packages, services }"

krisis.safeIdentity {
  value = unit;
  label = unit.label or null;
  source = unit.source or null;
  noun = "unit";
}
```

`safeShape` exposes only sorted attribute names for ordinary attrsets. `safeShapeWith { maxAttrs = 8; }` bounds that list.

`safeIdentity` prefers a validated label, then a source, then shallow shape. Do not use it at a boundary where evaluating label or source would violate an existing laziness guarantee.

## Collection helpers

```nix
diagnostics = krisis.collectDiagnostics [
  shapeDiagnostics
  ownershipDiagnostics
  (krisis.optionalDiagnostic conflict conflictDiagnostic)
];
```

Collection preserves group and item order. It does not catch exceptions or convert thrown callbacks into diagnostic records.

## Forcing boundaries

Safe rendering is about evaluation safety, not secrecy classification. It prevents accidental traversal, but an explicitly supplied label or message may still contain sensitive text.

Preserve these rules:

- never use `toJSON` or `toPretty` on arbitrary config payloads;
- guard derivation identity and names;
- never force `drvPath`, `outPath`, secret fields, provenance, or list elements merely to name a value;
- prefer validated author labels and source locations, then shallow shape;
- render known-safe claim and schema data separately from opaque payloads;
- add poison-value tests for every new rendering or contextual-evaluation branch.

## Verification

Krisis has a dedicated check and is also part of the full flake gate:

```fish
nix build .#checks.x86_64-linux.krisis -L
nix fmt
nix flake check -L
```
