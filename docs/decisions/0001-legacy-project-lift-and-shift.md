# ADR 0001: Retain Legacy Source Authority During Lift-and-Shift

- Status: Accepted for adoption
- Date: 2026-11-25
- Decision owners: project maintainers
- Baseline evidence: `sha256:f1863381ce5e10eb895997eff51a10416091d507516deda145836c3ea8d6a1d3`
- Shim parity evidence: `sha256:b4c4dd98c9003ccc90e9d4ff7b19272d1a8c6d908c9c7b930a7d6a5e652f6871`

## Context

Phase 1 proved the original project end-to-end. Phase 1.1 proved that Literate AI can
drive the same build, test, package, and CI stages through first-class wrapper
source-to-specification transfer has occurred.

## Decision

Move the complete original tree, preserving its internal taxonomy, from quarantine to
`components/legacy-project-wrapper/implementation`. The wrapper Component owns this retained implementation
and `litai.harness.mk` invokes it at its new location. Each move uses `git mv` when the
entry is tracked and plain filesystem move otherwise.

The move is admitted only when the post-move wrapper workflow has the same successful
exit and source-authority tree identity as the Phase 1 direct baseline. Only then is
the empty quarantine directory removed. The retained implementation is not generated
source, not a cache, and not a specification; it remains release authority until a
separate Phase 2 ADR qualifies native Components, Flavors, skills, and assets.

## Consequences

- `components/legacy-project-wrapper/implementation/` is intentionally load-bearing
  retained source and may not be cleaned as a build product.
- Build products still belong outside authority and remain fungible.
- Future migration items replace one retained surface at a time, prove parity, then
  remove its pre-adoption implementation with `git rm` or `rm`.
- Phase 2 owns source-to-specification and native rewrite; this ADR makes no semantic
  equivalence claim beyond E2E parity.
