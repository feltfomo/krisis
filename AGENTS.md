# Krisis

Krisis owns diagnostics for functional configuration libraries. Read `docs/README.md`, the relevant source, its callers, and its tests before changing a contract. Read `docs/qualification.md` for the supported dependency and forcing contracts. Maintained source and tests define shipped behavior; planning records don't authorize expanded scope.

## Think in types and effects

Design as a functional programmer. Start with the domain's products, sums, refinements, and elimination rules. Give each invariant one owner and each public operation a clear input, result, and failure contract. Use the simplest type that expresses the requirement. Dependent types and proofs need a concrete obligation they settle.

Use nix-effects' types and combinators as the shared vocabulary. `nix/qualified-source.nix` owns the corrected plain source exported as `lib.qualifiedNixEffectsSource`; consumers import it with their own `lib`, then share that `fx` instance with Krisis and application computations. `nix/dependencies.nix` imports the same tree. Keep the vendored upstream bytes and notices intact; build-time parity against the immutable upstream plus maintained patch owns verification and the existing `qualified-nix-effects` package. Don't re-export all of nix-effects. Read the pinned implementation before choosing an API. The public `fx.types`, `fx.bind`, `fx.send`, `fx.handle`, and `fx.effects.scope` APIs are the starting points. Upstream documentation sometimes describes exports absent from the curated public value. Don't reach through `src`, `_internal`, or `experimental` to make an example work.

Keep diagnostic data, effectful programs, and interpretation policy separate. A program describes the diagnostic operations it needs. A handler chooses collection or termination. Rendering consumes an explicit presentation projection. Avoid hidden tracing, ambient configuration, catch-all exception conversion, and subsystem-specific branches in the core.

Compose pure transformations with `|>` when it improves the data flow. Compose computations with `fx.bind`, `fx.map`, or the appropriate upstream combinator. The pipe operator applies a function; it doesn't bind an effect. Prefer explicit named functions over overloaded punctuation. Don't build a second effect runtime, type checker, or generic schema framework.

Nix still determines evaluation behavior. State which fields an operation may force. Keep opaque payloads outside structural inspection and serialization. A runtime contract isn't a static proof, and a thunk carrier only protects transport; it doesn't prove the captured value's type.

## Evaluation and cost

Successful evaluation mustn't force diagnostic context, unused locations, derivation internals, or discarded list elements. Preserve original callback exceptions with `builtins.addErrorContext` at the expression actually forced. `tryEval` catches a limited class of failures and loses the original exception text. Use it only at the documented safe-description boundary.

The pinned nix-effects interpreter deeply forces handler state after every effect. Transport arbitrary values through its public `fx.state.mkThunk` carrier and recover them at the documented boundary. Test the whole effect path with throwing values. Shielding the input alone doesn't protect an accumulator that later stores the raw value.

Choose algorithms and data layout before implementation. Avoid repeated list append, rescanning accumulated diagnostics, or closure chains that defer all previous updates. Collection should do constant work per event and one final linear traversal, excluding type checking and requested rendering. Explain an allocation or repeated check in a hot path. Measure before adding specialized machinery or making speed claims.

Keep independent validation applicative when errors can accumulate safely. Sequence dependent work only after valid input exists. A collecting type-check handler may resume after failure; its continuation value isn't evidence that the value is valid. An abort requires the interpreter's `abort` protocol, not `resume = false`.

## Writing

Write and review Nix code with these conventions. Use `with pkgs; [ ... ]` for package lists instead of repeating `pkgs.` on each entry. Group assignments with a shared attribute prefix into a nested attribute set, such as `services = { ...; };`, instead of repeating that prefix on separate assignments.

Use the `technical-writing` skill for engineering prose, API documentation, comments, and commit descriptions. Preserve precise FP terminology and follow the local comment conventions below.

Write concrete prose with contractions. Explain the contract, the non-obvious decision, and the failure behavior. Use FP terms when they name the actual mechanism. Don't turn the API guide into a type-theory lecture.

Source comments explain why. Use lowercase except for exact identifiers, no colons, no emoji, no divider comments, and no numbered narration. Review every comment in a touched file. Preserve required legal notices. A necessary history comment names the artifact and observed failure, stays in past tense, and takes at most two lines.

Avoid filler, rhetorical questions, repeated summaries, decorative formatting, and invented terminology. Keep roadmap identifiers and agent names out of source, comments, commit messages, and tags. Maintained docs describe shipped behavior; planned behavior stays in the planning records until implemented.

## Verification and delivery

Read the live development and gate instructions before running tools. `nix/toolchain.nix` supplies Nix and nix-unit 2.35.1 to devenv and the flake shell. Enter `devenv shell`; run `krisis-test` with suite paths for focused checks, `krisis-fmt` for formatting, and `krisis-gate` for the full gate. Outside the shell, `devenv test` selects that same graph. `tests/default.nix` owns every suite and receives the pinned assertions module path from both entry points. `flake.nix` owns `checks.tests`; `tools/workspace.py` admits tracked and non-ignored candidate files before staging. CI prepares check dependencies with `devenv shell python3 tools/workspace.py prepare`, then runs the same offline gate. Preparation never runs the suite. Use the repo's pinned toolchain. The host uses Lix; nix-unit needs its compatible Nix evaluator. Don't change host configuration or substitute lix-unit without a scope ruling.

Test boundaries, poison values, error paths, handler isolation, ordering, and dependent short-circuiting. Compare safe projections rather than deep-forcing an entire result containing opaque values. Use nix-unit's expected-error assertions. Run focused verification, then the maintained full gate. Record actual exits and limitations.

Scratch work belongs in `.runtime/<task-name>` and stays ignored. Start multiline shell scripts with `set -euo pipefail`. Never change `HOME`, edit `/etc/skadi`, or run destructive cleanup outside the standing rules. Commands handed to the user must be fish-safe. No agents or background harnesses without permission.

Remove disposable owned runtime artifacts and obsolete snapshots before handoff. Retain only evidence still needed for review or landing, and state its purpose. Remove retained scratch once that obligation is released. Preserve planning/archive records and other sessions' work. Follow the standing deletion rules, using only literal absolute paths you created inside the authorized scratch location; never use variables, globs, command substitution, `~`, or `$HOME` in deletion paths.

Stage exact paths only after approval. Show the complete commit subject, body, and path list before committing, and wait for the user's go-ahead. Never amend, rebase, tag, or push without an explicit request.
