# Krisis

Krisis is the shared diagnostic and safe-rendering library for `_lib` subsystems. It provides a small structured diagnostic record, caller-controlled formatting, aggregated throwing, and bounded descriptions of values that may contain derivations, secrets, or throwing fields.

It is a maintainer API, not an aspect-authoring surface.

## Exports

```nix
krisis = import ./modules/_lib/krisis { inherit lib; };
```

| Function | Purpose |
| --- | --- |
| `mkDiagnostic` | Validate and construct a diagnostic record. |
| `renderDiagnostics` | Render a list with caller-provided formatting. |
| `throwDiagnostics` | Render and throw a list. |
| `safeRender` | Render bounded scalar information without traversing arbitrary payloads. |
| `safeShape` | Describe type or shallow attrset shape. |

## Constructing diagnostics

```nix
krisis.mkDiagnostic {
  severity = "error";
  code = "program/directory-source-missing";
  message = "source does not exist in the flake";
  primary = {
    label = "directories[0]";
    source = "modules/aspects/example.nix";
  };
  notes = [ "git-backed flakes omit untracked files" ];
  help = "add a tracked file or remove the declaration";
  context = {
    index = 0;
  };
}
```

Required fields are strings:

- `severity`
- `code`
- `message`

`primary`, when present, is an attrset accepting only optional string fields `label` and `source`.

The constructor also preserves optional `secondaryLabels`, `notes`, `help`, and `context`. Those fields are intentionally caller-shaped; rendering policy belongs to the subsystem that owns the diagnostic.

## Rendering

Krisis does not impose one global visual format. The caller supplies the renderer:

```nix
krisis.renderDiagnostics {
  diagnostics = diagnostics;
  formatHeader = count: "example: ${toString count} error(s)";
  formatDiagnostic = diagnostic:
    "  - [${diagnostic.code}] ${diagnostic.message}";
  separator = "\n";
}
```

`formatHeader` defaults to no header. Returning `null` omits it. `separator` defaults to a newline.

To throw the same text:

```nix
krisis.throwDiagnostics {
  diagnostics = diagnostics;
  formatHeader = count: "example: ${toString count} error(s)";
  formatDiagnostic = diagnostic:
    "  - [${diagnostic.code}] ${diagnostic.message}";
}
```

Aggregate diagnostics before throwing when errors are independent. Do not stop at the first malformed declaration if the rest can be inspected safely.

## `safeRender`

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
- lists render only when every item is a safely recognized scalar;
- functions render as `<function>`;
- attrsets render as `<unrenderable value>` unless recognized as derivations;
- derivations render as `<derivation NAME>`;
- a missing, throwing, or non-string derivation name becomes `?`;
- failed attempts fall back to `<unrenderable value>`.

`safeRender` does not recursively serialize arbitrary attrsets.

## `safeShape`

`safeShape` is more conservative and better for payload identity:

```nix
krisis.safeShape {
  services = { ... };
  packages = [ ... ];
}
# "{ packages, services }"
```

Behavior:

- derivations render as `<derivation NAME>`;
- ordinary attrsets expose only sorted attribute names;
- all other values render as `<TYPE>`.

Use it when a diagnostic needs to distinguish an unlabeled unit without touching its values.

## Forcing boundaries

Safe rendering is about evaluation safety, not secrecy classification. It prevents accidental traversal of values, but an explicitly supplied label or message may still contain sensitive text. Callers remain responsible for what strings they put into diagnostics.

Preserve these rules:

- never use `toJSON` or `toPretty` on arbitrary config payloads;
- test derivation identity through a guarded `tryEval`;
- never force `drvPath`, `outPath`, secret fields, or list elements merely to name a value;
- prefer author labels and source locations, then fall back to `safeShape`;
- render known-safe claim and schema data separately from opaque payloads.

## Maintainer notes

`mkDiagnostic` validates the core fields because malformed diagnostics should fail at their source. It does not validate optional subsystem-specific context.

`renderDiagnostics` is intentionally policy-free. Program, Furnish, and Ownerships each own their headers and item wording while sharing one data shape and throwing mechanism.

Any expansion of safe rendering must include poison-value tests proving that the new branch does not force unrelated fields.

## Verification

```fish
nix fmt
nix flake check -L
```
