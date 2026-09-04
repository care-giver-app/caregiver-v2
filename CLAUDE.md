# CLAUDE.md — Caregiver v2

Orientation for working in this repo. **Read "How we work" before doing anything else** — it governs
what may be built and when.

## What this is

A multi-tenant family care-tracking app. AWS-native, iOS-first. Trevor's family uses it in
production today, on a small subset of what the product is meant to be. Trevor is the only person
working on it, and is a software developer rather than a designer.

The app is being reshaped, one area at a time, to match `docs/PRD.md`.

## How we work

**`docs/PRD.md` is the only document that describes the product.** When it and the app disagree, the
app is what changes. There are no other specs. The ones that existed were deleted rather than
maintained, because a document nobody can keep current lies with authority. Do not create new ones.
`docs/PRDWorkspace.md` stages raw ideas until they are merged into the PRD. **Use the `prd` skill**
(`.claude/skills/prd/`) whenever you touch either.

Work moves through gates. **Never begin a gate before the one before it is approved.**

Two whole-app passes come first, in this order:

1. **Screen catalog** — every screen in the app: its scope, its contents, and every exit with its
   destination and whether it is a sheet or a push. It lives inside `docs/PRD.md`, interleaved into
   the `## UX flows` sections, replacing the mermaid flow diagrams. Reviewed one area at a time.
2. **Data model** — the target entities: what exists, what each holds, what owns what, and what
   changes to live production data cost. Gates every endpoint change that follows.

Then each area runs this loop, each step gated on the one before it:

**Figma** → **endpoints** → **build and ship**

Area order: **Getting in → Trackers → Home → Team → Settings.** Trackers precedes Home because
Home's needs-attention section is defined in terms of tracker state. **Insights is deferred** and
out of scope until Trevor pulls it back in; it gets a named placeholder so no flow dangles.

### Rules that bind this work

- **Approved means merged to `main`.** Not "Trevor said it looks good in chat" — a gate advances
  when its PR is merged and the ledger below is updated in the same commit.
- **Never resolve an ambiguity silently.** A screen with an unanswered question gets `??? (open
gap)` in its catalog entry and a bullet in that flow's _Gaps in this flow_. Guessing something
  plausible and writing it in the PRD's confident voice is the failure mode this process exists to
  stop.
- **If implementation contradicts the PRD, stop and propose a PRD change.** Do not fix it in code
  and mention it afterward. That inversion is how the app got fragile.
- **Figma review needs no screenshots.** Give Trevor the file key, page, section, and node IDs; he
  reviews in Figma and approves in chat.
- **Never implement past the current gate**, however obvious the next step looks.
- **Branch off `main`, open PRs, never merge.** Trevor merges — merging to `main` deploys to prod,
  where his family is.

### Where we are

Update this table in the same commit that advances a gate. `—` not started · `draft` presented,
awaiting approval · `approved` merged to `main`.

| Area       | Screen catalog | Figma UI | Endpoints | Built |
| ---------- | -------------- | -------- | --------- | ----- |
| Getting in | —              | —        | —         | —     |
| Trackers   | —              | —        | —         | —     |
| Home       | —              | —        | —         | —     |
| Team       | —              | —        | —         | —     |
| Settings   | —              | —        | —         | —     |
| Insights   | deferred       | deferred | deferred  | —     |

**Data model pass:** — (gates every Endpoints cell above)

## Layout & modules

| Path                                      | What                                                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `docs/PRD.md`                             | **The product.** The only document describing what is being built.                                |
| `docs/PRDWorkspace.md`                    | Staging area for raw ideas, cleared as they merge into the PRD.                                   |
| `docs/adr/`                               | Architecture decision records. Still live.                                                        |
| `docs/archive/`                           | Historical design records from F1/B1/B3a/C1. Dated records of decisions made — never updated.     |
| `docs/runbook.md`, `docs/TECH_DEBT.md`    | Operations, and known deferred items.                                                             |
| `shared/openapi/openapi.yaml`             | **Contract source of truth** (OpenAPI 3). Everything else is generated from it.                   |
| `shared/go-common/`                       | Go module: `domain` (entities), `store` (DynamoDB repos), `auth`. Pinned **Go 1.23.7**.           |
| `shared/types-go/`                        | Generated Go types (Go 1.24.3). Do not hand-edit `*.gen.go`.                                      |
| `shared/types-swift/`, `shared/types-ts/` | Generated Swift / TS clients.                                                                     |
| `api/`                                    | Go Lambda HTTP API. `cmd/lambda/mux.go` wires routes; `internal/{handlers,middleware,httpx}`.     |
| `services/`                               | Async/scheduled Lambdas. Empty for now.                                                           |
| `infra/`                                  | AWS CDK (TypeScript). `lib/{shared,api,observability,billing}-stack.ts`, `bin/app.ts`.            |
| `ios/`                                    | The iOS client. `ios/design-system.md` catalogs existing components; `ios/fixtures.md` is the one |
|                                           | canonical persona/roster/tracker set — bind every Figma frame and SwiftUI preview to it.          |
| `web/`                                    | Web client. Not started, and out of scope until iOS matches the PRD.                              |

Go module paths are all `github.com/care-giver-app/caregiver-v2/...`. `api` has a `replace` for
`go-common`.

## Conventions & gotchas (the things that bite)

- **Go version is pinned at 1.23.7** for `go-common` and `api`. **Do NOT run `go get …@latest`** — it
  bumped a `go` directive to 1.25 once and broke CI. `testcontainers-go` is pinned to `v0.35.0` to
  hold the line. CI runs Go **1.24**; `types-go` is **1.24.3**.
- **OpenAPI → codegen.** After editing `shared/openapi/openapi.yaml`, regenerate:
  `cd shared/types-go && make codegen`. CI has a **codegen-drift check** that fails if anything
  differs — commit the regenerated files.
- **Pre-commit hooks (lefthook):** Prettier `--check` on staged TS/JSON/MD/YAML (run
  `pnpm exec prettier --write` first), commitlint (**Conventional Commits, lowercase subject start**),
  and an openapi-codegen hook.
- **Tests need Docker** (testcontainers + `amazon/dynamodb-local:2.5.2`) for the Go suites.
- Default region `us-east-2` (billing `us-east-1`). PR → `deploy-dev`; `main` → **prod**.

## iOS app (`ios/`)

Native SwiftUI (iOS 17+), generated from `ios/project.yml` via **XcodeGen** (the `.xcodeproj` is
gitignored — run `xcodegen generate` after pulling or editing `project.yml`). Consumes the generated
`CaregiverAPI` Swift client + **Amplify** (Cognito auth), sending the Cognito **ID token** via a
client middleware. A path-gated **macOS CI job** builds + tests on PRs touching `ios/**`.
**Gotchas:** every `xcodebuild` needs `-skipPackagePluginValidation`; the API base URL is injected
per-stage from `Config/{Dev,Prod}.xcconfig` → Info.plist (`API_BASE_URL`).

## Domain model as built today

This describes what exists, not what the PRD wants — closing that distance is the work.

Tenant = **`CareGroup`** (the PRD calls it a **care team**); `care_group_id` scopes every record.
Tables: `caregiver-{stage}-{user,care-group,membership,invitation,receiver,tracker,event}`
(multi-table, per `docs/adr/0011-*`). A `User` (keyed by Cognito `sub`) joins groups via
`Membership(role: admin|caregiver)`; a care group owns **receivers**, each receiver owns
**trackers**, and an **event** (the PRD calls it an **entry**) is logged against a tracker.
`care_group_id` is denormalized onto tracker/event rows so authz is a single read. Authz is
structural: `httpx.RequireMember`/`RequireAdmin` against `auth.AuthContext`. **Admins manage
Receivers/Trackers; all members log Events.**

- **Identity is JIT-provisioned** (read-first) in `api/internal/middleware/auth.go` from verified JWT
  claims. **Clients must send the Cognito _ID token_** (it carries `email`/`name`). The pool uses
  email as the username.
- **Invites:** admin-role invites require the accepting user's email to match; caregiver invites are
  token-first (supports Apple "Hide My Email"). No outbound email — invites are discovered in-app.

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

# iOS (Xcode 26+, XcodeGen). project.yml is the source of truth — never hand-edit the .xcodeproj.
cd ios && xcodegen generate && open Caregiver.xcodeproj      # to work in Xcode
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation                               # CLI build + test
```
