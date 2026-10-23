# nix-effects validation corrections

`nix-effects-validation.patch` applies to revision
`55ec2657c3c37e178c7730992a0f510739c1f945`. `nix/dependencies.nix` owns
the patched source and imports its curated public API. Consumers must use
that owner so qualification and library imports share the correction.

The upstream `Record.check` rejects undeclared fields, but `Record.validate`
only visits declared fields. The patch emits one `extra-field` event per
undeclared name at its `Field` position. It supplies `null` as the event's
value and never reads the undeclared field's value. A handler must treat
the event as failure evidence rather than rechecking that placeholder.

At each record, extra names appear first in lexical order, followed by
declared fields in lexical order. Child validation keeps its existing
order. Invalid outer shapes emit their existing shape error without
descending. Open records keep their existing behavior.

Upstream `Maybe` uses aggregate membership checking during effectful
validation, which discards child paths. The correction accepts null
without invoking the inner validator. Other values delegate through
`descendV` with the inherited path. That helper decrements fuel and emits
`deriveBounce` when the native descent budget runs out. Membership
checking, kernel construction, and guards are unchanged.

`tests/qualification/nullable.nix` covers null bypass, ordinary and throwing
failures, nested extras and refinements, record/list/variant composition,
opaque values, and fuel exhaustion. These regressions pass with the
corrected dependency. They don't establish the complete supported fragment.

The patched source retains upstream's MIT license, including the copyright
and permission notice. No project licensing policy was found. This record
doesn't claim compatibility with a project policy or select a Krisis license.

Variant validation and its host guard reject non-string tags before lookup.
The generic variant walker and error description also guard tag shape, so
kernel membership's strict error path doesn't coerce malformed tags.

Named and unnamed refinements share one verifier. Accepted bases run the
added predicate once; rejected bases are revisited only for located child
failures and skip the added predicate. Existing kernel witnesses retain
their interpretation. The generic unit field walker reports each undeclared
name under the resolved constructor, respecting open extras and discriminator
metadata. It doesn't use collecting elaboration.

The maintained qualification tree covers these corrections and composition.
See [the qualification contract](../docs/qualification.md) for the supported
fragment, cost rationale, effect protocol, and forcing matrix.

Mixed refinement guards preserve raw base constraints. Fully represented
kernel witnesses use kernel conjunction; kernel-sufficient bases can use the
new witness directly. Otherwise a raw guard conjoins `base.check` with the
existing derived witness interpretation. That fallback claims no kernel
proof for a raw predicate. Named and unnamed factories share this owner.
