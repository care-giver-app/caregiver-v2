# 0003 — OpenAPI 3 as Contract Source of Truth

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

Backend (Go), web (TypeScript), and iOS (Swift) all consume the same API. We need a contract that keeps them in sync without hand-maintained DTOs per language.

## Considered Options

- **OpenAPI 3** — REST-shaped, mature codegen for Go/TS/Swift, plays well with API Gateway.
- **gRPC / Protobuf** — stronger typing, but API Gateway doesn't natively speak gRPC; would force ALB+Fargate.
- **Hand-written types per language** — simplest setup, requires discipline to keep in sync.

## Decision

OpenAPI 3. `shared/openapi/openapi.yaml` is the source of truth. Generated clients (Go server stubs, TS client, Swift client) are committed and produced in CI.

## Consequences

### Positive

- Single contract, three consumers.
- Mature tooling: `oapi-codegen`, `openapi-typescript`, `swift-openapi-generator`.
- Plays directly with AWS API Gateway and Lambda.

### Negative / Trade-offs

- REST-only; streaming and bidirectional patterns need other mechanisms.
- Generated code must be regenerated and committed on every spec change.

## Related

- Spec: §6
- ADR-0002
