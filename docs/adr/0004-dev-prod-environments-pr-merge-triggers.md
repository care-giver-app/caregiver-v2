# 0004 — Dev + Prod Environments; PR → Dev, Merge → Prod

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

Solo dev wants to ship quickly while not breaking the live app for his family. The environment topology and promotion model need to support both goals at near-zero infra cost.

## Considered Options

- **Dev + prod** — PRs deploy to dev (clobbering), merge to main deploys to prod.
- **Dev + staging + prod** — auto-promote to staging on merge, manual gate to prod.
- **Ephemeral PR envs + prod** — each PR gets its own stack.
- **Just prod, trunk-based** — every merge ships, flags as the safety net.

## Decision

Dev + prod. PR open/update deploys to dev (clobbers any prior PR's state). Merge to `main` deploys directly to prod, no manual gate. Feature flags via AppConfig provide the runtime safety net.

## Consequences

### Positive

- Real environment for integration testing before users see anything.
- Cost ≈ $0 — pay-per-use AWS services sit idle.
- Cheap, fast promotion (a git merge).

### Negative / Trade-offs

- Multiple open PRs race for the dev environment. Acceptable for a solo dev.
- No staging means prod-only bugs surface in front of real users; mitigated by flags.

## Related

- Spec: §7
- ADR-0005 (feature flags)
