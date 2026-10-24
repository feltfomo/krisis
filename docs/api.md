# API reference

Initialize `k = inputs.krisis.lib.krisis { inherit lib fx; };` using the
[consumer setup](getting-started.md#consumer-setup). This page covers the exports
of [`src/default.nix`](../src/default.nix). Krisis doesn't re-export nix-effects.

- [Data contracts](#data-contracts)
- [diagnostic](#diagnostic)
- [path](#path)
- [report](#report)
- [validation](#validation)
- [inspect](#inspect)
- [suggest](#suggest)
- [render](#render)
- [nix](#nix)

## Notation and failures

Signatures show Nix application order. `f options value -> Result` means
`f options value` returns the described result. `{ field; optional ? default; }`
describes an argument record, not a copyable value. Names such as `Diagnostic`,
`Report`, `Checked a`, `Computation a`, and `Thunk a` describe runtime values.
They don't imply static checking by Nix.

A `Computation a` is a nix-effects program that produces `a` when interpreted.
Use `fx.pure`, `fx.bind computation (value: nextComputation)`, and `fx.map` to
compose it. `|>` applies a pure function; it doesn't bind effects.
`Thunk a` is the public `fx.state.mkThunk value` carrier. Recover a value through
`fx.state.forceThunk carrier` at the boundary that needs it. The carrier protects
transport from deep forcing; it doesn't prove the captured value's type.

Malformed controls and runtime contract violations raise evaluation exceptions.
Unknown option fields are rejected, including fields whose values would otherwise
remain unused. An ordinary validation rejection emits diagnostics and returns
`Invalid`. When validation forces an input, a throw remains an exception.
Predicate and callback exceptions also retain their original errors. Krisis uses `builtins.addErrorContext` at requested callback
results; it doesn't recover exception text or convert arbitrary exceptions into
diagnostics. The limited fallback in [inspection](#inspect) is the sole
safe-description boundary.

## Data contracts

### Diagnostics

`Diagnostic` is the normalized record below. Construction checks the envelope
and required message presence; presentation checks are deferred until requested.

| Field | Contract | Default |
| --- | --- | --- |
| `code` | Required nonempty string | None |
| `severity` | `"error"`, `"warning"`, or `"info"` | `"error"` |
| `message` | Required string | None |
| `primary` | Location or null | `null` |
| `related` | List of `{ location; message ? null; }`, where message is null or a string | `[]` |
| `notes` | List of strings | `[]` |
| `help` | Null or a string | `null` |
| `context` | Arbitrary opaque value | `null` |

Only these fields are accepted. Context has no inspection or presentation
contract. The diagnostic presentation projection has all these fields except
`context`. Counting a diagnostic doesn't demand its message, locations, related
entries, notes, or help. Requesting a field checks it; requesting the full
projection checks every presentation field, even if a formatter ignores it.

### Locations and ranges

A location is a closed record with these normalized fields:

| Field | Contract | Default |
| --- | --- | --- |
| `label` | Null or a string | `null` |
| `source` | Null or a caller-owned source identifier string | `null` |
| `path` | Structured path | `[]` |
| `range` | Null or `{ start = { line; column; }; end = { line; column; }; }` | `null` |

A location needs a nonnull label, nonnull source, or nonempty path. A range
requires a source. Lines and columns are integers starting at one; the end is
exclusive and must be at or after the start. Equal endpoints describe a point.
Krisis reads no source file and infers no provenance, expression extent, or
byte/Unicode coordinate conversion. Callers own those conventions.

A related entry requires `location` and accepts only that and `message`.
Its optional message is null or a string. Location defaults merge by attribute
name; a supplied `primary = null` clears them.

### Structured paths

A path is a list of single-field segments:

| Segment | Contract |
| --- | --- |
| `{ field = name; }` | String field name, including empty or quoted names |
| `{ index = n; }` | Zero-based nonnegative integer |
| `{ variant = tag; }` | String variant tag |
| `{ upstream = position; }` | Closed upstream Position metadata |

An upstream position requires `_tag = "Position"` and nonempty string `tag`,
`segment`, and `intent`. `rule` is null or a string, default null. Parameters
`name`, `idx`, and `layer` default to null. `Field`, `Tag`, and `Case` require a
string `name`; `Elem` and `Tuple` require a nonnegative integer `idx`; `DConLayer`
requires a nonnegative integer `layer`. These tags reject unrelated nonnull
parameters. Other tags, including unfamiliar ones, require null parameters and
retain their common metadata. No other fields are accepted. Unknown names fail
before their values are inspected; functions and nested payloads aren't metadata.

The validation adapter maps upstream `Field`, `Elem`, and `Tag` to `field`,
`index`, and `variant`. It retains other positions in `upstream` without
reinterpreting their tags. Paths describe blame; they don't authorize inspecting
the original payload.

### Checked and Outcome

| Description | Runtime record | Elimination |
| --- | --- | --- |
| `Checked a`, valid | `{ _con = "Valid"; value = Thunk a; }` | `validation.andThen` recovers the value for dependent work |
| `Checked a`, invalid | `{ _con = "Invalid"; }` | Skip dependent work; there is no value |
| `Outcome a`, success | `{ _con = "Success"; value = Thunk a; }` | Inspect the constructor, then recover the requested value |
| `Outcome a`, failure | `{ _con = "Failure"; }` | There is no successful value |

`Checked` records validation acceptance. `Outcome` records the interpreter's
completion status. For `report.run {} (validation.check options value)`, a
successful outcome contains a `Checked` record, which contains its own thunk.
For `report.run {} (fx.pure value)`, it contains the application value directly
inside the outcome thunk. A collecting type-check handler's resumed placeholder
isn't acceptance evidence. Only `Valid` permits dependent work.

### Reports

`Report a` is returned by the diagnostic interpreter:

| Field | Shape |
| --- | --- |
| `diagnostics` | Normalized diagnostics in emission order, including hidden events |
| `visibility` | Parallel list of decisions defined below |
| `summary` | `{ total; hasErrors; bySeverity = { error; warning; info; }; byCode; }` |
| `outcome` | `Outcome a` |

Counts are integers. `byCode` is an attribute set mapping exact codes to counts.
`bySeverity` counts effective severities. `hasErrors` means the error count is
positive; it doesn't capture explicit failure at a lower severity. Summary
operations inspect the envelope, leaving presentation and context deferred.
Report renderers expect this interpreter-owned shape, not arbitrary records with
application fields.

### Policy and visibility

| Policy field | Contract | Default |
| --- | --- | --- |
| `warningsAsErrors` | Boolean | `false` |
| `minimumSeverity` | `"info"`, `"warning"`, or `"error"` | `"info"` |
| `suppressCodes` | List of exact code strings | `[]` |

Only these policy fields are accepted. Policy applies in this order:

1. Promote warnings to effective errors when requested.
2. Count effective severities and update failure state.
3. Apply the severity threshold and exact-code suppression for display.

Each visibility decision contains `originalSeverity`, `effectiveSeverity`,
`suppressed`, `belowThreshold`, and `visible`. The last three fields are booleans;
`visible` is true exactly when neither suppression nor threshold hides the event.
Hidden events still count and can fail the report. Explicit failure always fails,
even for info severity with `hasErrors = false`.

### Handler composition

`report.handlers.collecting` and `report.handlers.strict` return nix-effects
configurations with `state`, `handlers`, and `return`. They own state fields
`{ head; count; failed; }` and a return projection that produces a Report.
Treat `head` as private. Extra handlers receive `{ param; state; }` and must return
`{ resume; state; }` or `{ abort; state; }`. Preserve the owned fields; put
application state under separate fields and update with `state // { ...; }`.
State is deeply forced after each effect. Store arbitrary application values in
public `fx.state.mkThunk` carriers before returning state.

Krisis owns `krisis.emit`, `krisis.fail`, and `krisis.context`. Passing `handlers`
to the configuration constructor rejects collisions with these keys. Merging
another record afterward with Nix `//` bypasses that protection and is the
caller's responsibility. Extra effects go to supplied handlers, rotate outward
through a scope, or reach the outer interpreter's explicit unhandled-effect error.
`resume = false` resumes with false; termination requires the `abort` protocol.

Use `fx.handle config computation` for a complete interpreter. Use public
`fx.effects.scope.runWith config computation` to embed the diagnostic interpreter
in a larger program. [interpretation.nix](../examples/interpretation.nix) shows
rotation and a custom return projection while preserving the owned report return.
[Qualification](qualification.md#handler-scope-and-policy-contracts) explains
state forcing and scope constraints.

### JSON version 1

`render.json` serializes this diagnostic envelope:

```nix
{ schemaVersion = 1; kind = "diagnostic"; diagnostic = k.render.project diagnostic; }
```

`render.projectReport` returns the exact record serialized by `render.jsonReport`:

| Field | Representation |
| --- | --- |
| `schemaVersion` | Integer `1` |
| `kind` | `"report"` |
| `diagnostics` | Visible diagnostic projections in emission order, plus `originalSeverity` and `effectiveSeverity`; `severity` equals effective severity |
| `summary` | `total`, `hasErrors`, `bySeverity` with `error`, `warning`, `info`, and `byCode` as a lexical list of `{ code; count; }` |
| `outcome` | `{ status = "Success"; }` or `{ status = "Failure"; }`, without a value |

Counts include hidden events. Optional fields normalize to null or empty lists
as described above. Locations and paths retain their structured form. Code counts
use a list because Nix gives special coercion meaning to attribute names such as
`__toString` and `outPath`. Object keys serialize in Nix's deterministic attribute
order. Diagnostic, related, and note lists retain their original order. Repeated
output has no timestamps or inferred host metadata.

`builtins.fromJSON` recovers presentation data, not the opaque original report.
The allowlist omits context, raw validation inputs, upstream error trees, handler
state, functions, and application values. Serialization doesn't inspect arbitrary
values to make them serializable. Presentation strings remain caller-owned data
and may contain sensitive text.

## diagnostic

### diagnostic.make

`k.diagnostic.make args -> Diagnostic`

Accepts the [diagnostic fields](#diagnostics), applies their defaults, and rejects
unknown fields, invalid code or severity, and a missing message. It checks only
the envelope immediately. Message type, locations, related entries, notes, and
help are checked when requested. Context remains opaque.

```nix
k.diagnostic.make {
  code = "service/port";
  message = "choose another port";
  primary = {
    source = "services.nix";
    path = [ (k.path.field "ports") (k.path.index 0) ];
  };
}
```

### diagnostic.factory

`k.diagnostic.factory { namespace ? null; severity ? "error"; primary ? null; } args -> Diagnostic`

Returns a constructor with bound defaults. Namespace is null or a nonempty string;
a nonnull namespace prefixes the required local code with `/`. Severity accepts
the diagnostic severities. Primary is deferred location metadata. Call fields
use the diagnostic contract. Call severity overrides the default, and call primary
fields override matching default fields while retaining the others. Explicit null
clears primary. Unused location defaults stay lazy. Invalid namespace, severity,
or unknown default fields fail at configuration; other checks follow `make`.

```nix
(k.diagnostic.factory {
  namespace = "service";
  primary.source = "services.nix";
}) {
  code = "port";
  message = "choose another port";
  primary.label = "web";
}
```

This has code `"service/port"` and both the source and label in its primary location.

### diagnostic.types

`k.diagnostic.types -> Attrset`

These are upstream runtime descriptions, distinct from admitted
[validation descriptions](#validationtypes):

| Export | Describes |
| --- | --- |
| `severity` | The three diagnostic severity strings |
| `nonempty` | Nonempty strings |
| `coordinate` | Integers at least one |
| `point` | Closed `{ line; column; }` coordinates |
| `range` | Ordered closed `{ start; end; }` points |
| `location` | A normalized location with its presence and source constraints |
| `presentation` | The complete normalized diagnostic record without context |
| `checked` | Generated datatype specification for Checked |
| `outcome` | Generated datatype specification for Outcome |

The first seven expose the upstream description interface, including
`description.check value -> Bool`; malformed or throwing values can raise
exceptions. For example, `k.diagnostic.types.coordinate.check 0` is false.
`checked` and `outcome` are public HOAS datatype specifications with `.T` describing
the generated form, rather than validation adapter inputs. See
[qualification](qualification.md#dependency-and-supported-types) for their generic
walking contract. Runtime checks and thunk shapes aren't proofs of arbitrary host
predicates or captured value types.

## path

All operations use the [structured path contract](#structured-paths). Invalid
segments, unknown fields, and malformed position metadata raise exceptions.
Normalization inspects segment metadata, never the application value it locates.

### path.field

`k.path.field name -> { field = name; }`

Requires a string, including an empty string. Constructs and checks one segment.

### path.index

`k.path.index n -> { index = n; }`

Requires a zero-based nonnegative integer. Negative integers fail.

### path.variant

`k.path.variant tag -> { variant = tag; }`

Requires a string. Constructs and checks one variant segment.

### path.normalize

`k.path.normalize segments -> Path`

Requires a list. Checks every segment, normalizes missing upstream metadata
parameters to null, and preserves order. Unknown fields fail before their values
are inspected.

### path.render

`k.path.render segments -> String`

Normalizes the path and renders it starting at `$`. Fields use Nix identifier
escaping, indexes use brackets, and variants use `#` followed by a JSON string.
Other positions render their declared scalar metadata as JSON inside angle
brackets. Arbitrary attrsets aren't serialized.

```nix
k.path.render [ (k.path.field "a.b") (k.path.index 0) (k.path.variant "Some") ]
```

Result: `$."a.b"[0]#"Some"`.

## report

### report.emit

`k.report.emit args -> Computation null`

Describes an observation using diagnostic constructor fields. It checks the
envelope, applies dynamic defaults when interpreted, and transports the diagnostic
without forcing presentation or context. Collecting interpretation resumes with
null. An effective error marks the report as failed but allows the continuation
to run. Strict interpretation throws on that error.

### report.fail

`k.report.fail args -> Computation a`

Accepts the same fields and defaults as `emit`. Collecting interpretation records
the diagnostic and aborts its continuation, producing Failure regardless of severity
or visibility. Strict interpretation throws its formatted diagnostic. The result
notation `a` doesn't promise a continuation value; this operation terminates.

### report.withContext

`k.report.withContext { namespace ? null; severity ? "error"; primary ? null; } computation -> Computation a`

Provides scoped diagnostic defaults with public scope rotation. Only supplied
fields override the enclosing scope. A nested namespace replaces the outer one;
primary fields merge as factory defaults do, and explicit null clears primary.
Diagnostic call fields override the scope. A normalized diagnostic already has
explicit severity and primary, so those fields override scope defaults too.
Namespace and severity are checked at entry; unused location metadata stays lazy.
Unknown fields fail. Exiting restores enclosing defaults, and siblings are isolated.
See [locations.nix](../examples/locations.nix).

### report.run

`k.report.run { policy ? {}; mode ? "collecting"; handlers ? {}; formatter ? null; } computation -> Report a`

Interprets a computation using [policy](#policy-and-visibility) and optional
[extra handlers](#handler-composition). Collecting mode retains all emitted events;
completion with an effective error produces Failure. Warning-only completion
succeeds. Explicit failure aborts even at info severity. Arbitrary successful
values remain thunked.

`mode` accepts only `"collecting"` and `"strict"`. Strict mode throws at the first
effective error or explicit failure, even when hidden. It renders that diagnostic
with effective severity using `render.plain`, or a supplied `formatter`. Requested
presentation failures remain evaluation failures. Warnings continue normally.
`formatter` must be null or a function returning a string from a complete diagnostic
projection. Collecting mode checks its function shape but never invokes it.
Invalid configuration, handler collisions, and unhandled effects raise exceptions.

### report.handlers.collecting

`k.report.handlers.collecting { policy ? {}; handlers ? {}; formatter ? null; } -> HandlerConfig`

Returns `{ state; handlers; return; }` for collecting interpretation with the same
policy, formatter validation, errors, and report return as `run`. Use it with
`fx.handle` or `fx.effects.scope.runWith`. Follow the owned-state and collision
rules in [handler composition](#handler-composition).

### report.handlers.strict

`k.report.handlers.strict { policy ? {}; handlers ? {}; formatter ? null; } -> HandlerConfig`

Returns the corresponding strict configuration. It has the same state and return
contract as collecting, and the terminal behavior of `report.run` in strict mode.

## validation

### validation.types

`k.validation.types -> Attrset of supported descriptions`

Use `T = k.validation.types` in the signatures below. Each expression returns a
Krisis-admitted description for `validation.check`, not an upstream type object
with a public `.check` method. There are no optional constructor arguments.
Compound constructors require admitted children, including unselected branches
and children of empty lists or null values. Raw upstream/custom type objects are
rejected. Don't construct admission records yourself. Admission is a runtime usage
contract, not an unforgeable brand, proof, or security boundary. General dependent
types, proofs, and third-party verifiers aren't supported.

| Expression | Accepted input / behavior |
| --- | --- |
| `T.String` | Nix strings |
| `T.Int` | Integers, excluding floats |
| `T.Bool` | `true` or `false` |
| `T.Float` | Floats, excluding integers |
| `T.Attrs` | Any attrset; doesn't inspect attribute values |
| `T.Path` | Nix path values, not strings |
| `T.Function` | Nix functions; doesn't inspect argument or result shape |
| `T.Unit` | Only `null` |
| `T.Null` | Only `null` |
| `T.Any` | Any value, left opaque, including a throwing thunk |
| `T.Record fields` | Closed record of `name = admittedType` fields; requires declared fields and rejects extras |
| `T.ListOf type` | List with every element checked against `type` |
| `T.Maybe type` | `null` or a value of `type`; null skips inner validation |
| `T.Variant branches` | `{ _tag = name; value = payload; }` with `name` selecting an admitted type in `branches` |
| `T.Either left right` | `{ _tag = "Left"; value = payload; }` checked against `left`, or `"Right"` against `right` |
| `T.refine base predicate` | A value accepted by `base` and then `predicate`; name is generated from the base |
| `T.refined name base predicate` | The same refinement with the supplied string diagnostic type name |

`fields` and `branches` are attribute sets. Refinement predicates normally have
shape `value: Bool`; the corrected upstream also interprets its public kernel
predicate witnesses, such as `fx.types.positiveInt`. A host predicate isn't kernel
proof evidence. A rejected base skips the added predicate and retains child
failures. An accepted base evaluates the added predicate once without another
structural validation walk. Rejected bases are revisited to recover located
failures. Throws stay exceptions; a nonboolean predicate result is an evaluation
error. Forcing follows the chosen type's required structure; opaque children stay
opaque. See [qualification](qualification.md#dependency-and-supported-types) for
refinement and kernel boundaries.

For example, `T.Variant { Some = T.Int; None = T.Unit; }` checks
`{ _tag = "Some"; value = 42; }`, while `T.Maybe T.Int` checks plain `42` or `null`.
A required `T.Maybe` record field must still exist. At each record, extra names
produce individual failures in lexical order before declared fields are visited
in lexical order. Extra values aren't read. Lists retain zero-based order;
variant paths append the selected tag without a synthetic `value` segment;
nullable descent adds no path segment. Invalid outer shapes don't descend.

### validation.check

`k.validation.check { type; code; location ? null; } value -> Computation (Checked a)`

Requires an admitted type and nonempty diagnostic code. Checks control names when
the configuration is applied, then type admission before code when the value
application is demanded. Bind the configured partial application once to reuse its
lazy configuration checks across values. Constructing that function leaves type,
code and location unevaluated. Every value application runs validation and the
required predicates with fresh scoped failure state.

Each upstream `typeCheck` event is authoritative failure evidence; the adapter
retains `deriveBounce` and never treats resumed placeholders as valid values. Ordinary rejection emits error diagnostics and returns
Invalid. Acceptance returns Valid containing the original value in a thunk.

Location is optional deferred [location metadata](#locations-and-ranges). It isn't
inspected for valid input or envelope-only failure summaries. Requested failure
presentation validates it and appends validation blame to its path. Each failure's
outer value shape is demanded with `builtins.typeOf`, preserving thrown inputs
that might otherwise appear to be rejection. Diagnostic context contains only
`validation = { path; reason; expected; actual; }`, with a structured blame path,
reason, expected type name, and outer type name. It contains no raw input.
Thrown inputs and predicates remain exceptions with checking context.

See [Getting started](getting-started.md#check-input-before-using-it) for a complete
record/refinement example with observed output.

### validation.all

`k.validation.all checks -> Computation (Checked [a])`

Requires a list of checked computations. Evaluates independent checks in list
order and accumulates ordinary failures. Returns Invalid if any check is Invalid;
otherwise returns Valid with a thunked list of their recovered values, preserving
order. An empty list succeeds with an empty value list. It doesn't convert thrown
exceptions into ordinary failures. Bookkeeping and carrier transport don't force
opaque accepted values; recovering and using those values may force them.

### validation.andThen

`k.validation.andThen f computation -> Computation b`

Requires a checked computation and callback `value: Computation b`. Calls `f` with
the recovered value only after Valid. On Invalid it skips `f` and returns a pure
Invalid. A callback may return another checked computation or an application result;
callers must account for Invalid on the skipped branch. Original callback exceptions
remain exceptions, with dependent-validation context at the callback application.
This doesn't force every lazy child of a returned record.

## inspect

Inspection returns bounded descriptions, not serialization of arbitrary values.
It uses Nix's limited `tryEval` boundary: some throws/assertions can fall back;
not every evaluator error, abort, or nontermination can. Bounds aren't a general
evaluator budget or secrecy guarantee. List length and attribute-name enumeration
still observe structure; supplied strings may contain sensitive data. Malformed
options fail outside fallback handling on every branch.

### inspect.value

`k.inspect.value { maxStringLength ? 256; maxListItems ? 32; fallback ? "<unrenderable value>"; } value -> String`

Bounds must be nonnegative integers; fallback must be a string. Scalars render as
JSON. Strings and paths truncate at the string bound and append `…` when omitted;
paths discard string context. Functions show `<function>`. Arbitrary attrsets use
the fallback. Derivations show only a guarded name as `<derivation name>`, using
`?` for a missing, throwing, or nonstring name, without inspecting derivation
internals.

Lists render only a prefix of scalars, with ` (+N more)` for omitted elements.
A non-scalar in the prefix uses fallback. Omitted elements stay uninspected, though
the list length is observed. Catchable root/prefix failures use fallback.

```nix
k.inspect.value { maxListItems = 2; } [ 1 2 (throw "unused") ]
```

Result: `[1,2] (+1 more)`.

### inspect.shape

`k.inspect.shape { maxAttrs ? 32; } value -> String`

Requires a nonnegative integer bound. Shows sorted shallow attribute names, with
an omission count, or `<type>` for other values. Derivations use guarded identity
`<derivation name>` without traversing internals. Unlike `inspect.value`, this
operation doesn't bound the derivation name length. Catchable root failures use
`<unrenderable value>`. Attribute values remain opaque except for guarded derivation
identification through `type` and `name`.

### inspect.identity

`k.inspect.identity { value; label ? null; source ? null; noun ? "value"; } -> String`

Requires value presence, string noun, and null-or-string label/source. Prefers
`"${noun} '${label}'"`, then `"${noun} at ${source}"`, then
`"${noun} ${k.inspect.shape {} value}"`. All controls are checked even when an
earlier preference wins. A label or source avoids inspecting value. Unknown fields
and invalid controls fail.

## suggest

### suggest.nearest

`k.suggest.nearest { maxDistance ? null; } input candidates -> String | null`

Requires a string input, a list of strings, and a null or nonnegative integer
bound. The default distance bound is 1 for input lengths up to 4, otherwise 3.
Uses nixpkgs' `levenshteinAtMost`, tightening the bound as it finds candidates.
Exact matches win; equal-distance ties retain the first candidate. Empty candidates
or no match returns null. Candidate string types are checked before the search,
even if an early exact match would win. Invalid inputs or controls raise exceptions.

`k.suggest.nearest {} "cat" [ "bat" "car" ]` returns `"bat"`.

## render

Diagnostic entry points take diagnostic constructor fields. Report entry points
take a Report. Input kind is explicit. All use the same validated diagnostic
[presentation projection](#diagnostics), removing context before inspection.
Requested presentation checks all its fields. Report presentation uses recorded
visibility and effective severity; hidden presentation fields remain deferred.
No report renderer recovers `outcome.value`. Presentation failures propagate.

### render.project

`k.render.project diagnostic -> Presentation`

Constructs and deeply checks the complete normalized record containing severity,
code, message, primary, related, notes, and help. Context is never read.

### render.projectReport

`k.render.projectReport report -> ReportPresentation`

Returns the fully checked [JSON version 1 report record](#json-version-1).
Projects visible diagnostics, named scalar/count summary fields, and outcome status.
It retains counts for hidden events, and both original and effective severity for
visible events.

### render.plain

`k.render.plain diagnostic -> String`

Renders a complete diagnostic projection. The first line has severity, `[code]`,
optional primary location, and message. Locations include every supplied label,
source, range, and path. Ranges display as
`source:startLine:startColumn-endLine:endColumn`. Subsequent lines contain related
locations and messages, then notes, then help, preserving order. Continuation lines
of multiline messages are indented. No source files are read.

`k.render.plain { code = "minimal"; message = "message"; }` returns
`"error [minimal] message"`.

### render.plainReport

`k.render.plainReport report -> String`

Validates the report presentation and joins visible diagnostic text with newlines.
It doesn't append summary or outcome text. No visible diagnostics produces `""`.

### render.json

`k.render.json diagnostic -> String`

Serializes the [version 1 diagnostic envelope](#json-version-1) using `builtins.toJSON`.
It validates the full diagnostic projection and never reads context.

### render.jsonReport

`k.render.jsonReport report -> String`

Serializes `render.projectReport report`. It has the same visibility and forcing
contract. See [json.nix](../examples/json.nix) for opaque payload transport.

### render.custom

`k.render.custom formatter diagnostic -> String`

Requires a function `Presentation: String`. It validates the complete diagnostic
projection before invoking the formatter, then checks the result is a string.
Nonfunctions and nonstring results fail. Callback throws keep their original error
with `builtins.addErrorContext` around the result actually forced; there is no
`tryEval` fallback.

`k.render.custom (p: "${p.code}: ${p.message}") { code = "example"; message = "notice"; }`
returns `"example: notice"`.

### render.customReport

`k.render.customReport formatter report -> String`

Requires a function `ReportPresentation: String`. It validates the entire version 1
report projection before invoking the formatter, even if the callback ignores
fields. Function/result checks and exception behavior match `render.custom`.

## nix

### nix.module

`k.nix.module report -> { assertions = [ { assertion; message; } ]; warnings = [String]; }`

Returns an ordinary module fragment with one assertion. Its boolean condition tests
Outcome success, including explicit info-level failure with zero counted errors.
The lazy failure message renders all retained diagnostics with effective severities,
including hidden explanations. Visible effective warnings become warning strings;
info stays report data, and promoted warnings participate in failure. Suppression
and thresholds never change validity. A successful application value stays opaque.

The assertion condition doesn't request presentation. Warning strings request only
visible effective warning presentations. Demanding a failed assertion message
requests every retained diagnostic's presentation; malformed or throwing fields
there remain exceptions. Context and application values stay untouched.

Import this fragment alongside assertion/warning option declarations.
`lib.evalModules` alone doesn't enforce assertions. A consumer must check the
conditions before returning its application result. The pinned nixpkgs consumer
uses public `lib.asserts.checkAssertWarn config.assertions config.warnings value`.
The [integration tests](../tests/integration.nix) use that helper after evaluating
the pinned assertions module. This establishes pure assertion consumption, not a
NixOS build or activation. [module.nix](../examples/module.nix) shows caller-owned
source and path attribution, including optional `unsafeGetAttrPos` with null handled.

### nix.withErrorContext

`k.nix.withErrorContext message value -> value`

Requires a string message and delegates to `builtins.addErrorContext`. Adds context
to exceptions when the wrapped expression is forced, preserving the original error.
Wrap the expression actually requested, such as a callback's selected field.
Wrapping a lazy record doesn't add context to an independently forced child.
It doesn't convert callback exceptions into diagnostics.
