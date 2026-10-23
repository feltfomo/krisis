# Qualified boundary and development contract

Krisis still exports the Axiom-based API in [README.md](README.md). This
contract records executable qualification for its replacement. The small
interpreters under `tests/qualification` are fixtures, not another public
library. The typed core must implement these contracts before replacing
the existing API.


## Dependency and supported types

`nix/dependencies.nix` applies `patches/nix-effects-validation.patch` to
nix-effects `55ec2657c3c37e178c7730992a0f510739c1f945`, then imports its
curated public value. Qualification and future library imports must use
this owner. The patched source is also available through the flake's
`packages.<system>.qualified-nix-effects`. Consumer imports use no private
paths, `exposeInternals`, or experimental namespaces.

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
The public `deriveBounce` handler remains installed.

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

The fixture bridge admits descriptions through its supported constructor
owner and explicitly rejects raw unsupported descriptions. Its admission
marker isn't a proof or security boundary. Kernel checking proves facts
about its represented fragment; a host predicate isn't kernel proof
evidence for arbitrary Nix code. A thunk carrier's shape doesn't establish
the type of its captured value.

Generic structural walking isn't a substitute for effectful refined
validation. Its guard helper reports aggregate guard failures rather than
nested host-refinement paths. The selected bridge uses corrected effectful
validation, with generic walking reserved for the generated domain forms.

## Results and paths

| Sum | Constructor record | Elimination |
| --- | --- | --- |
| Checked success | `{ _con = "Valid"; value = Thunk a; }` | Invoke dependent work only here. |
| Checked failure | `{ _con = "Invalid"; }` | Preserve failures and skip dependent work. |
| Report success | `{ _con = "Success"; value = Thunk a; }` | Recover only the requested value projection. |
| Report failure | `{ _con = "Failure"; }` | No successful value field exists. |

Independent checks retain all ordinary failures in input order. Dependent
checks eliminate `Checked`; an upstream resumed value can't establish
acceptance.

Path segments are `{ field = name; }`, `{ index = n; }`, and
`{ variant = tag; }`. Retain other positions as `{ upstream = position; }`.
Quoted names remain exact strings; presentation must quote them
unambiguously. Indexes are zero-based and nonnegative. Blame paths don't
authorize inspecting the original payload.

## Handler, scope, and policy contracts

Core effects will use `krisis.emit`, `krisis.fail`, and `krisis.context`.
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
corresponding projection is requested. Summaries mustn't inspect unused
location defaults. Preserve callback exceptions with `builtins.addErrorContext`
around the expression actually forced. Catch-all exception conversion isn't
supported.

## Development and source admission

Both environments select Nix 2.35.1 and nix-unit 2.35.1 through
`nix/toolchain.nix` from nixpkgs
`f13ff45afd1bb73e640eaa08a7066dbed07e3238`. `tools/workspace.py` enforces
exact nixpkgs lock identity and executable identities. Axiom is temporary,
pinned at `d56208631f0b89b8ff0a115105ad385017aaef23`. The original locked
Axiom lacked APIs required by the old tests; it wasn't a passing baseline.

Use the installed devenv 2.4.0 CLI. Its module input is locked from `v2.4.0`;
that source advertises module version 2.3.1. The version notice is upstream
metadata, not another selected evaluator.

```fish
devenv shell
krisis-test qualification.types
krisis-fmt
krisis-gate
```

`krisis-test` accepts zero or more nix-unit attribute paths from the single
`tests/default.nix` tree. `krisis-fmt` changes formatting. The gate checks it.
Outside the shell, `devenv test` selects the same full task graph as
`krisis-gate`: `check:format`, `check:nix`, `gate:flake`, then `gate:all`.
`krisis-gate` delegates directly to `devenv test`; neither appears in the
task commands, so the graph has no gate recursion. No status/modification
cache skips a task after source, example, or dependency
changes. The suite runs once in `checks.tests`; focused testing isn't a
second full-suite leaf.

The runner snapshots tracked and non-ignored untracked files before staging
and retains SHA-256 manifests in `.runtime/gate`. `.gitignore` owns scratch
exclusions; `nix/source.nix` consumes the same literal root paths for consumer
sources. Formatter/static scans use the admitted candidate files or their
snapshot. Runtime and devenv state stay outside those inputs.

The flake check uses a direct nix-unit expression with supplied sources, a
private local evaluation store, empty substituters, disabled fallback, and
the Nix build sandbox. It doesn't assign or export HOME. The outer gate also
requests offline operation and disables remote builders. Missing local
dependencies fail instead of fetching during the gate.

Both Linux systems remain declared. Native build/test evidence is
x86_64-linux. Evaluation of aarch64-linux doesn't establish execution there.
The host's Lix evaluator doesn't establish library compatibility on Lix.

Upstream MIT notices remain in the patched source. No project licensing
policy was found, and no policy compatibility or project license is claimed.

References: [pinned exports](https://github.com/kleisli-io/nix-effects/blob/55ec2657c3c37e178c7730992a0f510739c1f945/default.nix),
[Nix builtins](https://nix.dev/manual/nix/2.25/language/builtins),
[operators](https://nix.dev/manual/nix/2.25/language/operators),
[syntax](https://nix.dev/manual/nix/2.25/language/syntax),
[selected evaluator manual](https://nix.dev/manual/nix/2.35/).
