# Krisis

Krisis constructs typed diagnostics and interprets diagnostic computations through
nix-effects. Diagnostic data, computation, reporting policy, and presentation have
separate owners. Context and application values stay opaque.

## Import and basic use

Both imports take `{ lib, fx }`. `fx` must be the corrected nix-effects instance
provided by `nix/dependencies.nix`, described in [qualification.md](qualification.md).
The flake exports `lib.krisis`; it doesn't re-export nix-effects.

```nix
k = inputs.krisis.lib.krisis { inherit lib fx; };
# or
k = import ./src { inherit lib fx; };
```

[examples/basic.nix](../examples/basic.nix) is a runnable expression taking the
same arguments. The test suite evaluates it. It checks a record with a refined
port list, emits a located failure, and skips dependent work on invalid input.

```nix
let
  T = k.validation.types;
  check = k.validation.check {
    type = T.Record { ports = T.ListOf T.Int; payload = T.Any; };
    code = "service/shape";
    location.source = "caller-supplied.nix";
  };
in k.report.run {} (k.validation.andThen
  (value: fx.pure value.ports)
  (check { ports = [ 8080 false ]; payload = opaqueValue; }))
```

## Diagnostics and locations

`diagnostic.make` accepts a closed record with required nonempty `code` and
`message`. `severity` defaults to `"error"` and accepts `"error"`, `"warning"`, or
`"info"`. The normalized fields are `severity`, `code`, `message`, `primary`,
`related`, `notes`, `help`, and `context`. Their defaults are null for `primary`,
`help`, and `context`, and empty lists for `related` and `notes`.

```nix
k.diagnostic.make {
  severity = "warning";
  code = "service/port";
  message = "port isn't in the supported range";
  primary = {
    label = "web";
    source = "services.nix";
    path = [ (k.path.field "ports") (k.path.index 0) ];
    range = {
      start = { line = 3; column = 5; };
      end = { line = 3; column = 9; };
    };
  };
  related = [ { location.label = "other declaration"; message = "also contributes"; } ];
  notes = [ "ports are caller-owned configuration" ];
  help = "choose another port";
  context = opaqueValue;
}
```

A location accepts only `label`, `source`, `path`, and `range`, normalized to null,
null, empty list, and null. It must have a label, source, or nonempty path. A range
requires a source identifier. Coordinates are one-based line and column numbers;
the end is exclusive and must be at or after the start. Krisis reads no source
files and infers no provenance or byte/Unicode coordinate conversion.

Related entries contain a required `location` and an optional null-or-string
`message`. Notes are strings; help is null or a string. Context has no inspection
or presentation contract.

Construction checks field names, required field presence, code, and severity.
It defers presentation checks until the field is requested. For example, a summary
can count a diagnostic whose message throws, but requesting that message throws;
a non-string message fails its deferred check. `render.project` requests and checks
all presentation fields, detaching context first. Unknown constructor and control
fields fail even if their values would otherwise remain unused.

`diagnostic.factory { namespace ? null; severity ? "error"; primary ? null; }`
binds defaults and returns a diagnostic constructor. A nonnull namespace is a
nonempty string joined to the local code with `/`. Call severity overrides the
default. Call location fields override matching defaults, retaining other default
fields. An explicit `primary = null` clears the default. Unused location defaults
remain lazy.

`diagnostic.types` exposes the upstream descriptions `severity`, `nonempty`,
`coordinate`, `point`, `range`, `location`, and `presentation`, plus generated
`checked` and `outcome` datatype specifications. `presentation` describes the
normalized record without context. These runtime contracts don't prove arbitrary
host predicates. A thunk shape doesn't establish the captured value's type.

## Paths

`path.field name`, `path.index n`, and `path.variant tag` construct segments.
`path.normalize` validates a list containing `{ field = name; }`, `{ index = n; }`,
`{ variant = tag; }`, or `{ upstream = position; }`. Indexes are zero-based and
nonnegative. The validation adapter retains other upstream positions structurally
in `upstream`; it doesn't reinterpret their tag identities.

An upstream position is a closed record with `_tag = "Position"`, nonempty string
`tag`, `segment`, and `intent`, and optional null-or-string `rule`. The recognized
parameter fields are `name`, `idx`, and `layer`, normalized to null when absent.
`Field`, `Tag`, and `Case` require a string name; `Elem` and `Tuple` require a
nonnegative index; `DConLayer` requires a nonnegative layer. These tags reject
unrelated nonnull parameters. Other tags, including unfamiliar ones, retain their
common metadata and require null parameters. Unknown fields are rejected before
their values are inspected. Functions and nested payloads aren't position data.
Normalization and diagnostic locations use this same typed boundary.

`path.render` starts with `$`, quotes exotic field names with Nix identifier
escaping, renders indexes with brackets and variant tags as `#` followed by a JSON
string. Other positions render only the declared scalar position fields as a JSON
object inside angle brackets. No arbitrary attrset is serialized. Paths grant no
authority to inspect the original value.

## Effects, reports, and policy

`report.emit diagnostic` describes an observation and resumes with null.
`report.fail diagnostic` aborts the diagnostic interpreter, skips its continuation,
and always fails. Use `fx.bind` and `fx.map` to compose computations; `|>` applies
pure functions and doesn't bind effects.

`report.run { policy ? {}; mode ? "collecting"; handlers ? {}; } computation`
returns `diagnostics` in emission order, `summary`, `outcome`, and a parallel
`visibility` list. The summary has `total`, `bySeverity`, `byCode`, and `hasErrors`.
It inspects only the envelope. Diagnostics include hidden events.

The outcome is `{ _con = "Success"; value = Thunk a; }` or
`{ _con = "Failure"; }`. Recover a requested successful value through
`fx.state.forceThunk report.outcome.value`. Failure has no value field. Collected
effective errors mark completion unsuccessful while the computation may continue.
A warning-only run succeeds. Explicit failure remains unsuccessful even with an
info diagnostic and no counted errors.

Policy accepts `warningsAsErrors`, default false; `minimumSeverity`, default
`"info"`; and `suppressCodes`, default empty. Suppression matches exact code strings.
Effective severity is determined first, then failure and counts, then visibility.
Each visibility entry contains `originalSeverity`, `effectiveSeverity`, `suppressed`,
`belowThreshold`, and `visible`. Visibility cannot erase failure or diagnostics.

Strict mode throws on the first effective error or explicit failure, even if hidden.
Warnings continue. It uses `render.plain`, which requests the shared presentation
projection. A throwing presentation field therefore remains a real evaluation
failure at this terminal boundary.

`report.withContext { namespace ? null; severity ? "error"; primary ? null; } body`
provides dynamic defaults with public scope rotation. Only supplied fields override
the enclosing scope. Nested namespace overrides replace the namespace; locations
merge as factory defaults do. After exit the enclosing defaults are restored, and
siblings are isolated. Explicit diagnostic fields override dynamic defaults.
A previously normalized diagnostic already has explicit severity and primary fields.

For a larger interpreter, pass extra handlers to `report.run`, or pass
`report.handlers.collecting { policy ? {}; handlers ? {}; }` to `fx.handle`.
`report.handlers.strict` has the same interface. These configurations own state
`{ head; count; failed; }` and the return projection, and return a report. Extra
handlers must preserve this state or update it without replacing its owned fields;
put their own state under a separate field. Krisis owns `krisis.emit`, `krisis.fail`,
and `krisis.context`. Composition through `handlers` rejects key collisions.
Ordinary Nix `//` after obtaining a configuration can bypass that check and is the
caller's responsibility. Unrelated effects reach supplied handlers or the outer
interpreter's explicit unhandled-effect failure.

The collector stores a private persistent spine. Each event allocates one node and
thunk carriers for its payload and head, caches the previous pointer to weak head
normal form, and updates fixed scalar state. It neither copies nor forces the
existing spine. Both reports and successful `validation.all` results use the same
private finalizer. It allocates an indexed cursor list with `genList`, then forces
cursors from head to tail with `foldl'`. Each cursor follows one cached predecessor
through constant-time `elemAt`; reverse output indexes the settled cursors once.
The three loops do linear total work without associative duplicate tracking or
native recursion proportional to event count. Empty results don't demand the head.

This reasoning follows Nix 2.35.1's implementations of `genList`, `elemAt`, and
`foldl'` in [primops.cc](https://github.com/NixOS/nix/blob/2.35.1/src/libexpr/primops.cc).
It describes owned spine construction and finalization, excluding upstream
interpretation, type checking, and requested presentation. Summaries use a fixed
number of traversals and nix builtins for code grouping; no complexity claim is
made for that grouping. The fixed 10,000-event and 10,000-value tests check count,
complete order, and throwing-payload laziness. No latency or memory claim is made.

## Checked validation

`validation.types` owns the supported constructor interface. It provides `String`,
`Int`, `Bool`, `Float`, `Attrs`, `Path`, `Function`, `Unit`, `Null`, `Any`, `Record`,
`ListOf`, `Maybe`, `Variant`, `Either`, `refine`, and `refined`, with the corresponding
public nix-effects signatures. Descriptions close over actual corrected upstream
types. The adapter doesn't walk input structure itself or accept raw upstream/custom
type objects. Its runtime admission shape is a usage contract, not an unforgeable
brand, a proof of arbitrary predicates, or a security boundary. Don't construct
admission records yourself. General dependent types, proofs, and third-party
verifiers aren't supported.

`validation.check { type; code; location ? null; } value` produces a computation of
`Checked`, either `{ _con = "Valid"; value = Thunk a; }` or `{ _con = "Invalid"; }`.
Each upstream `typeCheck` event is authoritative failure evidence. The adapter
retains `deriveBounce`; it never rechecks a placeholder or treats resumed values as
validity evidence. Type, code, and control-option names are checked at the entry
boundary. Location is deferred presentation metadata: valid input and envelope-only
failure summaries don't inspect it. Requesting failure presentation validates the
location, its normalized paths, and source ranges. Located failures retain extras,
missing nullable fields, nested refinements, field names, indexes, and variant tags. Context records only validation
path, reason, expected type name, and outer shape; no raw input is attached.

`validation.all checks` evaluates independent checked computations in list order.
It accumulates ordinary failures and returns Valid with a thunked value list only
if every check is Valid. `validation.andThen f computation` calls `f` with the
unwrapped value only after Valid. Invalid has no successful value field. Aggregation
settles its counters and previous spine pointer before returning each computation,
including pure checks that bypass interpreter state forcing. Thrown inputs and
predicates remain evaluation failures. Supported refinement checking
has the acceptance and failure-path costs described in [qualification.md](qualification.md).

## Inspection, suggestions, and exceptions

`inspect.value options value` bounds scalar strings and scalar-list prefixes.
Options are `maxStringLength`, default 256; `maxListItems`, default 32; and `fallback`,
default `"<unrenderable value>"`. Bounds must be nonnegative integers. Scalars render
as JSON, paths discard string context, functions show `<function>`, and arbitrary
attrsets use the fallback. Derivations show only a guarded name, with `?` when the
name is missing, throwing, or not a string. Omitted list elements aren't inspected.

`inspect.shape { maxAttrs ? 32; } value` shows sorted shallow names or a type name,
with guarded derivation identity. `inspect.identity { value; label ? null;
source ? null; noun ? "value"; }` prefers label, then source, then shape. Identity
controls are checked even when an earlier preference wins.

Malformed options fail outside fallback handling on every branch. Thrown roots can
fall back within Nix's limited `tryEval` behavior. It catches some throws/assertions,
not every evaluator error, abort, or nontermination. Output bounds aren't a general
evaluator budget or secrecy guarantee. List length and attr-name enumeration still
observe container structure. Caller-provided strings can contain sensitive data.

`suggest.nearest { maxDistance ? null; } input candidates` uses nixpkgs'
`levenshteinAtMost`, tightening the bound as it finds candidates. The default bound
is 1 for input lengths up to 4, otherwise 3. Explicit bounds are nonnegative integers.
Exact matches win, equal-distance ties retain the first candidate, and no match or
an empty candidate list returns null.

`nix.withErrorContext message value` uses `builtins.addErrorContext`. Wrap the
expression actually forced, such as a callback's selected field. Wrapping a lazy
record doesn't add context to an independently forced child. Original exceptions
remain exceptions; Krisis doesn't convert callback throws to diagnostics.

## Presentation and development

`render.project diagnostic` returns validated normalized presentation data without
context. `render.plain diagnostic` supplies terminal severity/code/message output,
with a primary identity, notes, and help. Complete location/related rendering,
versioned JSON, the Nix module adapter, further executable examples, and CI aren't
implemented or exported yet.

The pinned environment supplies Nix and nix-unit 2.35.1. The source uses `|>`;
direct imports need Nix's `pipe-operators` feature. See
[qualification.md](qualification.md) for lock parity, offline sandboxing, source
admission, and the forcing contract.

```fish
devenv shell
krisis-test baseline extensions
krisis-fmt
krisis-gate
# the same full gate outside the shell
devenv test
```
