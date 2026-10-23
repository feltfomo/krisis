# Development

Use the repository's pinned shell for focused checks and the full gate. Consumer
setup is in [Getting started](getting-started.md). Dependency and forcing contracts
are in [Qualification](qualification.md).

## Toolchain and commands

Both environments select Nix 2.35.1 and nix-unit 2.35.1 through
`nix/toolchain.nix` from nixpkgs
`f13ff45afd1bb73e640eaa08a7066dbed07e3238`. `tools/workspace.py` enforces
exact nixpkgs lock identity and executable identities. The active dependency
graph and public import contract use only the corrected effect dependency.

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

## Source admission and offline checks

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

## CI preparation and verification limits

CI is configured in `.github/workflows/check.yml`. It installs Nix 2.35.1 and
the devenv CLI from the same locked devenv revision, then enters the shared shell.
The [checkout action](https://github.com/actions/checkout/blob/3d3c42e5aac5ba805825da76410c181273ba90b1/action.yml)
and [Nix installer](https://github.com/cachix/install-nix-action/blob/75c75c31ebece974e48ebc36b4ad125bd97bd97b/action.yml)
are pinned to inspected commits. The installer receives an explicit Nix release
URL, enables the sandbox, and disables its substitution override. No private cache
or separately configured secret is required.

Preparation runs `devenv shell python3 tools/workspace.py prepare`. It snapshots
the admitted candidate, evaluates the native check derivations, reads the pinned
Nix 2.35.1 version 4 derivation JSON, and builds their direct input derivations.
It rejects unsupported JSON versions and dynamic dependency outputs. It doesn't
build the check outputs or execute the suite. Ordinary fetching is allowed here.
The subsequent `devenv test` runs the same full gate described above, offline with
no substitution/fallback or remote builder recovery. There is no second suite leaf,
workflow dispatch, publication, or deployment. Local verification doesn't establish
a remote CI run. Action bootstrapping hasn't been executed on this host.

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
