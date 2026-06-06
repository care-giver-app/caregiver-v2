# 0001 — Parallel v2 over Evolve-in-Place

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

V1 of the Caregiver app is a working personal project used by Trevor and his brothers. We want to rewrite it for multi-tenant use, custom event types, customizable dashboards, and an iOS-native client. The rewrite needs better engineering rails (CI/CD, feature flags, observability, ADRs). The question is whether to evolve v1 in place or build v2 in parallel.

## Considered Options

- **Parallel v2** — new repo, new backend, new clients. V1 keeps running for the family unchanged until v2 is ready.
- **Evolve in place** — refactor v1 incrementally behind feature flags toward the v2 design.
- **Hybrid** — new backend (clean break on contracts), evolve clients in place to point at the new backend.

## Decision

Parallel v2. The app is small, traffic is low (single family), and Trevor does not plan many updates to v1. The cost of maintaining both during the transition is minimal; the cost of evolving inside v1's choices (hard-coded event types, no multi-tenant model) is high.

## Consequences

### Positive

- Clean slate for data model, contracts, and engineering practices.
- No coexistence complexity in code.
- V1 remains a safety net for the family during the rebuild.

### Negative / Trade-offs

- Two deployments to monitor during the transition.
- Existing data will need a future migration story (deferred to a B4-style spec).

## Related

- Spec: `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md` §2
