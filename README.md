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
| `docs/PRD.md`                 | **The product** — the only document describing it   |
| `docs/adr/`                   | Architecture decision records (MADR)                |
| `docs/archive/`               | Historical design records — never updated           |

## Quickstart

See [`docs/runbook.md`](docs/runbook.md) for the day-to-day dev loop and operational guides.
See [`docs/PRD.md`](docs/PRD.md) for what the product is, and `CLAUDE.md` for how work moves
through its approval gates.

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

See `docs/archive/2026-06-06-f1-engineering-practices-baseline-design.md` (historical).
