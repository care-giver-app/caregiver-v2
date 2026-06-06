# 0002 — Single Monorepo Over Polyrepo

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

V1 uses polyrepo (`care-giver-api`, `care-giver-site`, `care-giver-app-ios`, etc.). Polyrepo is sometimes claimed to be "best practice", but most of its benefits (team autonomy, blast-radius isolation) target multi-team orgs and don't apply to a solo developer. Polyrepo cost (contract drift, doubled CI config, harder cross-cutting refactors) hits a solo dev directly.

## Considered Options

- **Single monorepo** — everything in one repo, path-filtered CI.
- **Polyrepo per deployable** — separate repos for api, web, ios, infra; published shared types.
- **Split monorepo** — backend+web+infra together, iOS standalone.

## Decision

Single monorepo. iOS has minimal friction inside a monorepo (Xcode opens the `ios/` directory). Backend, web, infra, and shared contracts change together and benefit from one PR touching all of them.

## Consequences

### Positive

- One ADR folder, one spec folder, one place to grep.
- Contract changes can land in one PR with consumers updated.
- Simpler CI configuration with path filters.

### Negative / Trade-offs

- macOS runners needed in GitHub Actions for iOS jobs (slightly more expensive minutes).
- Repo clone size grows over time.

## Related

- Spec: `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md` §5
- ADR-0001
