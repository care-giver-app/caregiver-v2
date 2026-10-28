# 0013 — New API Beside the Old Until Cutover

- **Status:** Accepted
- **Date:** 2026-10-28
- **Deciders:** Trevor Williams

## Context and Problem Statement

ADR 0012 moves prod onto the target data model in one cutover, after every area is built. But
merging to `main` deploys to prod, where the family's installed app reads today's API and tables.
Each area's endpoints and build must be able to merge to `main` — which is what approval means —
without touching what the installed app depends on, for the months until cutover.

## Considered Options

- **New API under `/v1`** — the target contract lives in the same `openapi.yaml` under a `/v1`
  prefix, served by the same API, reading and writing only the new tables. New iOS screens sit behind
  an AppConfig flag (ADR 0005).
- **Long-lived `next` branch** — new work merges to a branch that deploys to dev; `main` stays frozen
  as prod until cutover merges `next` into it.

## Decision

**New API under `/v1`.** `main` stays deployable and every gate still advances by merging to it. Prod
receives the new code and the new, empty tables as each area lands, but nothing calls them until the
flag flips. A long-lived branch would drift from `main` for months and redefine "approved".

Cutover is then: run the ADR 0012 migration, flip the flag, ship the iOS build, and in a later
release delete the unprefixed paths and the old tables. `/v1` stays as the API's version prefix.

## Consequences

### Positive

- Every area merges to `main` and deploys like any other change.
- The new paths run in prod before cutover, so the cutover changes data and a flag, not code.

### Negative / Trade-offs

- Two generations of paths and schemas share one contract until cutover; new schemas take names that
  do not collide with the old (`MyAccount`, `TeamMembership`).
- The API reads both sets of tables until the old paths are removed.

## Related

- ADRs: 0005 (feature flags), 0012 (target data model)
