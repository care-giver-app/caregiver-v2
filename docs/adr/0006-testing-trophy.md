# 0006 — Testing Trophy Shape

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

We want enough testing to make solo iteration safe without paying the cost of an over-tested codebase. The stack (Lambda + DynamoDB + OpenAPI-generated types) has specific test economics: handlers are mostly orchestration, integration tests against DynamoDB Local give high confidence per unit of effort.

## Considered Options

- **Classic pyramid** — heavy unit, light integration.
- **Testing trophy** — heavy static analysis + integration, light unit, tiny E2E.
- **Integration diamond** — minimal unit, heavy integration, tiny E2E.
- **Pragmatic minimum** — tests only when something breaks twice.

## Decision

Testing trophy. Static analysis (TS strict, golangci-lint, OpenAPI-generated types) does the broad work. Integration tests against DynamoDB Local + LocalStack carry the bulk of confidence. Unit tests reserved for non-trivial logic. 1-3 E2E smoke tests per critical user flow.

## Consequences

### Positive

- Tests catch real bugs (handler-DB interactions) rather than mocked-away interactions.
- Low ceremony for orchestration code.
- Static analysis cost ≈ free.

### Negative / Trade-offs

- Integration tests run slower than unit tests.
- Testcontainers/LocalStack add a Docker dependency to local dev.

## Related

- Spec: §9
