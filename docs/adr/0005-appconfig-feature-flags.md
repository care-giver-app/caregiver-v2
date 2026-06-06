# 0005 — AWS AppConfig for Feature Flags

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

Feature flags are the runtime safety net for the trunk-based, no-staging promotion model (ADR-0004). We need a flag system that's cheap, native to AWS, and gives proper feature-flag semantics (targeting, % rollout) rather than ad-hoc toggles.

## Considered Options

- **AWS AppConfig** — native AWS, pay-per-fetch with Lambda extension caching, schema validation.
- **ConfigCat / LaunchDarkly free tier** — managed SaaS, better UX, third-party dependency.
- **Self-hosted (Unleash, GrowthBook, Flagsmith)** — open source, runs in our own infra.
- **Roll our own** — DynamoDB table + SDK.

## Decision

AWS AppConfig. One application per environment, single JSON profile per app with schema validation. Lambda extension provides in-process caching (default 45s TTL).

## Consequences

### Positive

- Native AWS, near-zero cost at our scale.
- Schema-validated config (catches typos at deploy).
- No external runtime dependency for flag evaluation.

### Negative / Trade-offs

- AppConfig UI is functional but not as polished as LaunchDarkly.
- Each flag's targeting logic must be implemented in our flag-evaluation code (no built-in user segmentation engine).

## Related

- Spec: §8
- ADR-0004
