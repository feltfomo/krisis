# Krisis

Krisis is the shared diagnostic and safe-rendering library for its consumers, lexicon among them. It provides validated diagnostic records, caller-owned reporting policy, contextual evaluation, collection helpers, and bounded descriptions of values that may contain derivations, secrets, or throwing fields.

It is a maintainer API, not an aspect-authoring surface.

## Import

```nix
# share the axiom version used by the consuming subsystem
krisis = inputs.krisis.lib.krisis { inherit lib axiom; };

# or directly, from a checkout of this repo
krisis = import ./src { inherit lib axiom; };
```

## Exports

| Function | Purpose |
| --- | --- |
| `mkDiagnostic` | Validate and construct one diagnostic record. |
| `mkDiagnosticFactory` | Bind default severity, code prefix, and primary location. |
| `qualifyCode` | Join a diagnostic namespace and local code. |
| `allowedSeverities` | Supported severity names. |
| `mkReporter` | Bind rendering, finishing validation results, and throwing policy once. |
| `validateType` | Adapt an Axiom runtime type into caller-coded diagnostics. |
| `renderPath` | Render zero-based structured validation paths. |
| `summarizeDiagnostics` | Count severities and codes without rendering messages or context. |
| `suggest`, `suggestWith` | Select a nearby vocabulary member with stable tie handling. |
| `editDistance` | Re-export nixpkgs' Levenshtein implementation. |
| `renderDiagnostics` | Render a list with caller-provided formatting. |
| `throwDiagnostics` | Render and throw a list. |
| `renderPlain` | Stock one-diagnostic code/label/message rendering with notes and help. |
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
  primary.source = "src/furnish/core.nix";
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
- `checked`, which returns a value only when the diagnostic list is empty;
- `finish result`, which unwraps an Axiom validation result or applies the reporter's failure policy.

`formatHeader` defaults to no header. Returning `null` omits it. `separator` defaults to a newline.

A subsystem without its own format can pass `renderPlain` as `formatDiagnostic`: it renders the code, optional primary label, and message on the first line, then notes and help indented beneath.

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

## Runtime type diagnostics

Use an Axiom runtime description when nested fields should retain precise paths:

```nix
parse = krisis.validateType {
  type = axiom.types.record {
    ports = axiom.types.listOf axiom.types.int;
    implementation = axiom.types.opaque;
  };
  code = "service/shape";
  label = "server";
  path = [ "config" ];
};

result = parse declaration;
value = reporter.finish result;
```

`type` and the complete diagnostic `code` are required. `label`, `source`, `severity` (default `error`), and a path prefix (default empty) are optional. Options are checked even when validation succeeds. Success preserves the parsed value; failure maps each neutral type issue to a Krisis record without attaching the input. `context.validation` contains only `path`, `expected`, `actual`, and `reason`. The normal message includes a rendered path and expected/actual outer shapes. The caller still owns the code and reporting policy.

`renderPath [ "config" "ports" 0 ]` returns `$.config.ports[0]`. Exotic field names are quoted, and numeric components are zero-based, non-negative indexes. Root is `$`. Attribute paths do not grant authority to read the original payload.

A type validator is not a safe renderer. A thrown input or predicate remains an evaluation error; it is not converted into a normal validation diagnostic. Use `opaque` for values that the boundary must not inspect.

## Summaries and suggestions

`summarizeDiagnostics diagnostics` returns `total`, `hasErrors`, `bySeverity` (always containing error, warning, and info), and `byCode` counts. It validates only the code/severity envelope and never renders messages, notes, or contexts. Counting diagnostics does not create a new failure policy. A warning still counts as a diagnostic when passed to `reporter.finish`; callers choose whether to separate severities first.

`suggest input candidates` returns the closest candidate within distance 1 for inputs of up to four characters, otherwise distance 3, or null. Equal-distance ties retain the first candidate. `suggestWith { maxDistance = 2; } input candidates` sets an explicit non-negative bound. Candidates must be strings. The implementation narrows the current best bound, uses nixpkgs' `levenshteinAtMost`, and does not sort all candidates. `editDistance a b` delegates to nixpkgs' `levenshtein`.

## Rendering limits

Thrown roots now return the same fallback as other unrenderable values. Malformed options still throw outside that fallback, including for function and derivation branches. Only the bounded output expression is attempted; raw payloads are never deep-forced. Nix `tryEval` catches throw/assert failures, not every evaluator error, abort, or nontermination. Output limits are not a general evaluation budget or secrecy guarantee.

## Evaluator compatibility

The source uses `|>` and the flake requests `pipe-operators`. On Nix 2.25, enable `extra-experimental-features = pipe-operators`, or accept this flake's setting. A raw `import ./src` does not apply flake configuration. The tested Lix development evaluator supports pipes without that flag and warns if given the Nix-only feature name. Keep Axiom and Krisis on compatible source revisions; Lexicon follows one Axiom input across both.

## Verification

The locked development environment provides focused tests and the full gate. See
[the qualification contract](qualification.md) for dependency corrections,
forcing boundaries, source admission, and toolchain ownership:

```fish
devenv shell
krisis-test
krisis-fmt
krisis-gate
# or run the full task graph from outside the shell
devenv test
```
