# Krisis documentation

Start with the [project overview](../README.md), then choose the page for your task.

- [Getting started](getting-started.md) sets up a consumer, collects and renders diagnostics, and composes validation.
- [API reference](api.md) documents every public operation, supported constructor, and data contract.
- [Dependency qualification](qualification.md) explains the corrected dependency, forcing boundaries, and collector constraints.
- [Development](development.md) covers the pinned shell, focused tests, full gate, source admission, and CI preparation.

## Executable examples

Each expression takes `{ lib, fx }` and is imported by the [shared example tests](../tests/examples.nix).
Use the imports from [Getting started](getting-started.md#consumer-setup) to supply those arguments.

- [basic.nix](../examples/basic.nix) checks a record with refined ports and skips dependent work on failure.
- [composition.nix](../examples/composition.nix) contrasts independent accumulation with dependent checking.
- [locations.nix](../examples/locations.nix) merges nested location defaults and restores the enclosing source.
- [interpretation.nix](../examples/interpretation.nix) embeds diagnostics in a larger effect interpreter and changes its return projection.
- [json.nix](../examples/json.nix) serializes a report while leaving context and a successful application value opaque.
- [module.nix](../examples/module.nix) returns assertions and warnings, with optional caller-owned attribute-position lookup.
