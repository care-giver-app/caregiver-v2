# CLAUDE.md — Caregiver v2

Orientation for working in this repo. Read `docs/roadmap.md` for what to build next and
`docs/TECH_DEBT.md` for known deferred items before starting.

## What this is

Greenfield, multi-tenant rewrite of a family care-tracking app. Built as a **parallel v2** (v1 still
runs for the family until v2 is ready — see `docs/adr/0001-*`). AWS-native, **iOS-first**.

**Status:** F1 (engineering baseline), B1 (data model & identity), and **B3a** (core care domain —
Receivers, Trackers, Events) are **done**. B3 was decomposed: **B3b** (Schedules,
NotificationPreferences, Audit read) is still planned. Next per the roadmap is **B3b** or **C1** (iOS
MVP — now unblocked). Each phase goes brainstorm → design spec (`docs/specs/`) → implementation plan
(`docs/plans/`) → implementation.

## Layout & modules

| Path                                      | What                                                                                                                                    |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `shared/openapi/openapi.yaml`             | **Contract source of truth** (OpenAPI 3). Everything else is generated from it.                                                         |
| `shared/go-common/`                       | Go module `…/shared/go-common`: `domain` (entities), `store` (DynamoDB repos), `auth` (AuthContext + predicates). Pinned **Go 1.23.7**. |
| `shared/types-go/`                        | Generated Go types (module `…/shared/types-go`, Go 1.24.3). Do not hand-edit `*.gen.go`.                                                |
| `shared/types-swift/`, `shared/types-ts/` | Generated Swift / TS clients.                                                                                                           |
| `api/`                                    | Go Lambda HTTP API (module `…/api`, Go 1.23.7). `cmd/lambda/mux.go` wires routes; `internal/{handlers,middleware,httpx}`.               |
| `services/`                               | Async/scheduled Lambdas (B2). Empty for now.                                                                                            |
| `infra/`                                  | AWS CDK (TypeScript). `lib/{shared,api,observability,billing}-stack.ts`, `bin/app.ts`.                                                  |
| `web/`, `ios/`                            | Clients (C-phases).                                                                                                                     |
| `docs/`                                   | `roadmap.md`, `specs/`, `plans/`, `adr/`, `runbook.md`, `TECH_DEBT.md`.                                                                 |

Go module paths are all `github.com/care-giver-app/caregiver-v2/...`. `api` has a `replace` for
`go-common`.

## Conventions & gotchas (the things that bite)

- **Go version is pinned at 1.23.7** for `go-common` and `api`. **Do NOT run `go get …@latest`** — it
  bumped a `go` directive to 1.25 once and broke CI. `testcontainers-go` is pinned to `v0.35.0` to
  hold the line. CI runs Go **1.24**; `types-go` is **1.24.3**. (See `docs/TECH_DEBT.md` for the
  standardize-on-1.24 plan.)
- **OpenAPI → codegen.** After editing `shared/openapi/openapi.yaml`, regenerate:
  `cd shared/types-go && make codegen`. CI has a **codegen-drift check** that regenerates TS + Go +
  copies the spec into `shared/types-swift/Sources/CaregiverAPI/openapi.yaml`, and fails if anything
  differs — so commit the regenerated files.
- **Pre-commit hooks (lefthook):** Prettier `--check` on staged TS/JSON/MD/YAML (run
  `pnpm exec prettier --write` first), commitlint (**Conventional Commits, lowercase subject start** —
  `feat: add x`, not `feat: Add x`), and an openapi-codegen hook that regenerates the TS client.
- **Tests need Docker** (testcontainers + `amazon/dynamodb-local:2.5.2`) for the Go integration +
  isolation suites.
- **Branch off `main`; open PRs; do NOT auto-merge** — Trevor merges (merging to `main` triggers a
  **prod deploy** via `cd-main`). PR → `deploy-dev`. Default region `us-east-2` (billing `us-east-1`).

## Commands

```bash
# Go (Docker required for store/handler/middleware tests)
cd shared/go-common && go test ./...
cd api && go test ./...

# Regenerate types after a contract change
cd shared/types-go && make codegen

# Infra
cd infra && pnpm test
cd infra && pnpm exec cdk synth --context stage=dev          # prod needs CAREGIVER_ALERT_EMAIL set
```

## B1 domain model (the substrate everything builds on)

Tenant = **`CareGroup`**; `care_group_id` scopes every record. Tables: `caregiver-{stage}-{user,
care-group,membership,invitation,receiver,tracker,event}` (multi-table, per `docs/adr/0011-*`). A
`User` (keyed by Cognito `sub`) joins groups via `Membership(role: admin|caregiver)`; a `care_group`
owns **receivers**, each receiver owns **trackers** (custom field schema + thresholds), and an
**event** is logged against a tracker (B3a). `care_group_id` is denormalized onto tracker/event rows
so authz is a single read. Authz is structural: every group-scoped request checks `auth.AuthContext`
via `httpx.RequireMember`/`RequireAdmin`. **Admins manage Receivers/Trackers; all members log Events.**

Full B3a design: `docs/specs/2026-06-12-b3a-core-care-domain-design.md`.

- **Identity is JIT-provisioned** (read-first) in `api/internal/middleware/auth.go` from verified JWT
  claims. **Clients must send the Cognito _ID token_** (it carries `email`/`name`; access tokens
  don't). The Cognito pool uses **email as the username**.
- **Invites:** admin-role invites require the accepting user's email to match; caregiver invites are
  token-first (supports Apple "Hide My Email"). No outbound email — invites are discovered in-app via
  `GET /invitations/mine`.

Full design: `docs/specs/2026-06-11-b1-data-model-identity-design.md`.
