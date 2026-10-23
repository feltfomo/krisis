# Dependency qualification and evaluation contracts

The [API reference](api.md) describes the supported operations and data. This
page records the corrected dependency, forcing boundaries, and implementation
constraints. Contributor commands and CI preparation live in
[Development](development.md).
The small interpreters under `tests/qualification` remain mechanism regressions;
they aren't production APIs or collector cost evidence.

## Dependency and supported types

`nix/dependencies.nix` applies `patches/nix-effects-validation.patch` to
nix-effects `55ec2657c3c37e178c7730992a0f510739c1f945`, then imports its
curated public value. Qualification and library imports must use
this owner. The patched source is also available through the flake's
`packages.<system>.qualified-nix-effects`. Consumers import that shipped source
with their own `lib`, then pass the resulting `fx` to Krisis and use it in their
application computations. Krisis initialization remains `{ lib, fx }`; it doesn't
re-export all of nix-effects. Consumer imports use no private paths,
`exposeInternals`, or experimental namespaces.

The qualified fragment is `String`, `Int`, `Bool`, `Float`, `Attrs`, `Path`,
`Function`, `Unit`/`Null`, opaque `Any`, closed `Record fields`, `ListOf type`,
`Maybe type`, `Variant branches`, and `Either left right`. Refinement forms
are `refined name base predicate` and `refine base predicate`. Compound and
nested refinements retain child failures. Thrown inputs and predicates
remain evaluation failures, not fabricated diagnostics.

The bridge uses effectful validation and owns every emitted `typeCheck`
event as failure evidence. It doesn't recheck an event's value or infer
validity from its continuation. Required nullable fields must exist. A
missing-field event remains a failure even when its type accepts null.
The public `deriveBounce` handler remains installed. On a failure event the
adapter demands `builtins.typeOf param.value` before emitting a diagnostic.
This forces only the failed value's outer shape and preserves thrown inputs
that upstream kernel membership can otherwise describe as rejection. Missing
and extra-field events carry upstream's null placeholder. No raw value is
stored in the diagnostic.

At each closed record, extra names produce individual `extra-field` events
in lexical order, then declared fields are visited in lexical order. Lists
retain zero-based order. Variants append the selected tag without a
synthetic `value` segment. Nullable descent adds no segment. Invalid outer
shapes don't descend. Extra values aren't read or attached to events.

Named and unnamed refinements share one verifier. It calls `base.check`
first. Accepted bases evaluate the added predicate once without another
structural validation walk. Rejected bases are revisited to recover located
failures and skip the added predicate. That failure-path traversal is
intentional. Kernel predicate witnesses retain their existing `deriveGuard`
interpretation. A kernel witness never erases a raw base guard. Fully
represented witnesses compose in the kernel; kernel-sufficient bases retain
the direct witness path; other bases use a raw conjunction with `base.check`. No performance number is claimed.

Generated `Checked` and `Outcome` use public `types.hoas.datatype`, `con`,
`field`, and `thunk`. The public generic unit walker qualifies their
constructor records, required fields, extras, and thunk carriers. Extras
precede the descriptor's existing child order; `_con` and `_tag` remain
constructor metadata. Descriptor `openExtras` continues to permit extras.
General indexed/dependent datatypes, proof terms, arbitrary custom type
objects, and third-party verifier callbacks aren't admitted.

The production adapter admits descriptions through `validation.types`, which
closes over the supported upstream constructors. Raw upstream and custom type
objects are rejected. Its eliminator shape isn't an unforgeable brand, proof,
or security boundary. The fixture bridge's marker isn't the production API.
Kernel checking proves facts
about its represented fragment; a host predicate isn't kernel proof
evidence for arbitrary Nix code. A thunk carrier's shape doesn't establish
the type of its captured value.

Generic structural walking isn't a substitute for effectful refined
validation. Its guard helper reports aggregate guard failures rather than
nested host-refinement paths. The selected bridge uses corrected effectful
validation, with generic walking reserved for the generated domain forms.

## Result and path boundaries

The [API data definitions](api.md#data-contracts) own Checked, Outcome, and path
shapes. Independent checks retain failures in input order; dependent checks
eliminate Checked before continuing. Paths describe blame without authorizing
inspection of the original payload.

## Handler, scope, and policy contracts

Core effects use `krisis.emit`, `krisis.fail`, and `krisis.context`.
Fixtures use a separate `qualification` namespace. Handlers are keyed by
strings. Krisis owns its keys; composition must reject collisions rather
than silently overwrite caller handlers. Unknown effects rotate outward
or reach the outer interpreter's explicit unhandled-effect failure.

Handlers receive `{ param; state; }` and return `{ resume; state; }` or
`{ abort; state; }`. Emission resumes with unit, represented by null.
`resume = false` continues. Explicit failure uses `abort`, skips its
continuation, and produces `Failure` regardless of visibility. An ordinary
warning-only computation completes successfully.

Policy order is fixed:

1. Determine effective severity, including warning promotion.
2. Update counts and monotone failure state.
3. Apply display threshold and exact-code suppression.

Visibility cannot erase failure or counts. Retain diagnostics in emission
order, including hidden diagnostics. A report contains diagnostics, summary,
outcome, and explicit visibility decisions. These envelope operations don't
render presentation fields or context.

The trampoline deeply forces state after each effect. Protect raw contexts,
diagnostics, accumulated payloads, and arbitrary returned values with public
`state.mkThunk` before they enter forced boundaries. Recover with
`state.forceThunk` at the owner of the requested projection. Protecting only
effect input is insufficient. The raw-state poison control must fail while
the protected path succeeds.

Use public `effects.scope.provide` for dynamic defaults. Scoped handlers
return protected defaults and rotate unrelated effects outward. Nested
defaults restore after exit and remain isolated between siblings. Mutable
reader updates aren't restoring scopes.

## Forcing matrix

| Operation | May inspect | Must defer |
| --- | --- | --- |
| Construction and emission | Field names, code, severity, explicit controls | Message, locations, related labels, notes, help, context |
| Summary and policy | Envelope and policy configuration | Presentation fields and context |
| Requested presentation | Its declared fields and checks | Context and raw config values |
| Checked success | Qualified type's required structure | Opaque fields and unrelated values |
| Safe inspection | Bounds and declared shallow/prefix observations | Opaque attr values, derivation internals, omitted elements |

Unknown options fail at construction. Deferred checks execute when the
corresponding projection is requested. A `validation.check` location is checked
when a requested failure diagnostic uses it. Successful validation and collected
summaries don't inspect unused locations. Type/code checks and unknown control
options remain immediate. Preserve callback exceptions with `builtins.addErrorContext`
around the expression actually forced. Catch-all exception conversion isn't
supported.

## Terminal presentation and module boundary

The [API reference](api.md#render) defines the exact diagnostic and report
entry points, formatter inputs, and version 1 JSON fields. Every renderer uses the
same validated diagnostic projection. Requested report presentation validates
visible diagnostics only, projects the summary's named scalar/count fields and
outcome status, and never reads successful application values. Original and
effective severity are both retained in report presentation. Suppression and
thresholds affect visibility, not outcome or counts. JSON round-trips through
`builtins.fromJSON` into presentation data, without opaque payloads.

Custom formatters receive the declared complete projection and must return strings.
Strict interpretation uses the same diagnostic projection and terminal renderer;
an optional formatter replaces its final string production. Callback exceptions
remain exceptions with context added at the demanded callback result. No exception
text recovery or arbitrary error conversion is promised.

Source coordinates are caller-owned one-based lines/columns with exclusive ends.
A range requires a source identifier. Structured paths and all supplied primary
and related location fields remain visible in plain and JSON presentation.
Krisis reads no source file and doesn't infer value provenance or coordinate units.

The module adapter consumes an existing report's outcome and visibility. Its one
assertion tests success directly. Its failure message, demanded only on failure,
renders all retained diagnostics so an explicit info-level failure remains
explainable even when hidden or when `hasErrors` is false. Visible effective
warnings alone become warning strings. Tests evaluate the pinned assertions option
module and then consume conditions through public `lib.asserts.checkAssertWarn`.
This is pure assertion enforcement evidence, not a NixOS build or activation.

Additional forcing boundaries:

| Operation | May inspect | Must defer |
| --- | --- | --- |
| Report presentation | Visible diagnostic projections, named summary fields, outcome constructor | Hidden presentation, context, outcome value |
| Module assertion condition | Outcome constructor | All presentation and application values |
| Module warning strings | Visible effective warning presentations | Other diagnostic presentations and application values |
| Failed assertion message | Retained diagnostic presentation | Context and application values |
| Custom formatter | Declared validated projection and callback result's string type | Opaque application data and context |

## Collector construction and finalization

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

## Verification limits

Both Linux systems remain declared. Native build/test evidence is x86_64-linux.
Evaluation of aarch64-linux doesn't establish execution there. The host's Lix
evaluator doesn't establish library compatibility on Lix. Local gate verification
doesn't establish a remote CI run or action bootstrapping. See
[Development](development.md) for the configured CI path and its limits.
