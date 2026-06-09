# Caregiver v2

Greenfield rewrite of the Caregiver tracking app. Multi-tenant, custom event types, real-time updates across iOS and web.

## Layout

| Directory                     | Purpose                                             |
| ----------------------------- | --------------------------------------------------- |
| `api/`                        | Synchronous HTTP API (Go Lambda)                    |
| `services/`                   | Async/scheduled Lambda services (one per directory) |
| `shared/openapi/`             | OpenAPI 3 contract — source of truth                |
| `shared/go-common/`           | Shared Go libraries                                 |
| `shared/types-{go,ts,swift}/` | Generated clients from OpenAPI                      |
| `web/`                        | Next.js + React web client                          |
| `ios/`                        | SwiftUI iOS client                                  |
| `infra/`                      | AWS CDK in TypeScript                               |
| `docs/specs/`                 | Brainstormed design specs                           |
| `docs/adr/`                   | Architecture decision records (MADR)                |
| `docs/plans/`                 | Implementation plans                                |

## Quickstart

See [`docs/runbook.md`](docs/runbook.md) for the day-to-day dev loop and operational guides.

### Prerequisites

- Node 20+, pnpm 9+
- Go 1.23+
- Xcode 16+ (for iOS work)
- Docker (for testcontainers)
- AWS CLI v2, configured

### First-time setup

```bash
pnpm install
pnpm exec lefthook install
```

## Architecture

See `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`.
