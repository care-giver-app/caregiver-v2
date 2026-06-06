# F1 — Engineering Practices Baseline

**Status:** Draft — pending user review
**Date:** 2026-06-06
**Author:** Trevor Williams (with Claude)
**Supersedes:** none (greenfield)

## 1. Purpose

Establish the engineering rails for the Caregiver v2 rewrite: contracts that don't drift, deploys that don't surprise, decisions that don't get lost, and observability that won't surprise-bill. Every choice optimizes for **solo-dev velocity at near-zero AWS cost** while building transferable skills.

This is sub-project **F1** in a larger decomposition. F1 is a *foundations* spec — it does not define any product feature. It establishes the substrate that B1, B2, B3, C1, C2, C3 will all build on.

## 2. Context

- v1 is a working app used by Trevor and his brothers to track care for their mother.
- v1 stack: Angular web, Go Lambda API, DynamoDB, multiple sibling repos under `CareGiverApp/`.
- v1 pain points: hard-coded event-type configs, no multi-tenant isolation, inconsistent CI/CD, no feature flag system, fragmented decision tracking.
- v2 will be built as a **parallel** system. v1 continues to run unchanged for the family until v2 is ready. (See ADR-0001.)

## 3. Goals

- **Fast solo iteration.** Anything that demands ceremony beyond what's necessary is removed.
- **Cost ≈ $0/mo** at current traffic (single family) and bounded growth beyond.
- **Transferable skills.** Choices favor tools and patterns common in modern AWS shops.
- **Safety nets** to compensate for solo-dev mistakes: feature flags, CDK diff in PRs, branch protection, observability guardrails.

## 4. Non-Goals

- Data model design (deferred to B1).
- API surface (deferred to B3).
- Auth/identity (deferred to B1).
- UI design (deferred to C1/C2/C3).
- Notification orchestration design — directory placement is defined here, but architecture is its own spec.
- v1 migration strategy (deferred; tentatively B4).

## 5. Repository structure

Single monorepo at `caregiver-v2/`:

```
caregiver-v2/
  api/                          # synchronous HTTP API (Go Lambda)
    cmd/lambda/                 # handler entry points
    internal/                   # business logic
    go.mod
  services/                     # async / scheduled / worker Lambdas
    notifications-orchestrator/
    notifications-executor/
    email-sender/
    digest/
    # ... future services go here
  shared/
    go-common/                  # shared Go libs (logging, config, dynamo, flags)
    openapi/
      openapi.yaml              # contract source of truth
    types-ts/                   # generated TS client (web + iOS optional)
    types-go/                   # generated Go server stubs
    types-swift/                # generated Swift client
  web/                          # Next.js 15+ / React 19+ (App Router)
  ios/                          # SwiftUI Xcode project, iOS 17+
  infra/                        # AWS CDK in TypeScript
    bin/app.ts
    lib/
      shared-stack.ts           # DynamoDB tables, SQS, SNS, AppConfig
      api-stack.ts
      notifications-stack.ts
      email-stack.ts
      digest-stack.ts
      web-stack.ts              # CloudFront + S3 + Lambda for SSR
  docs/
    adr/                        # MADR records
    specs/                      # brainstormed feature specs (this file lives here)
  .github/
    workflows/                  # path-filtered CI per package
  CLAUDE.md                     # AI assistant context
  README.md
```

**Conventions:**

- `api/` is reserved for the synchronous HTTP API. **Anything else is a service** under `services/<name>/`.
- Each service is an independent deployable: own Go module, own CDK stack, own CI path filter.
- Services communicate via **SQS / SNS / EventBridge**, never direct cross-service imports.
- Shared code lives in `shared/go-common/`. Promotion to shared requires it to be needed by ≥2 callers.
- Directory names are kebab-case and match their CloudFormation stack suffix (e.g., `services/email-sender/` → `CaregiverProd-EmailSender`).

## 6. Contracts — OpenAPI 3

- **Source of truth:** `shared/openapi/openapi.yaml`.
- **No handler ships without a spec change** (enforced by review discipline; ADR-0003 captures the rule).
- **Code generation** in CI on every change to `openapi.yaml`:
  - Go server stubs via `oapi-codegen` → `shared/types-go/`
  - TypeScript client via `openapi-typescript` + `openapi-fetch` → `shared/types-ts/`
  - Swift client via `swift-openapi-generator` → `shared/types-swift/`
- **Generated files are committed.** No surprise codegen at consumer install time.
- **Breaking changes** require a spec version bump and an ADR justifying the break.

## 7. CI/CD pipeline

**Environments:** `dev` and `prod`, both full CDK stacks in the same AWS account, separated by stack name prefix.

**Triggers:**

| Event | Action |
|---|---|
| PR opened/updated (from internal branch only) | Lint, type-check, build, run tests for affected packages; `cdk diff` posted as PR comment; `cdk deploy CaregiverDev` clobbering prior state |
| Merge to `main` | Run all tests; `cdk deploy CaregiverProd`; no manual gate |
| Tag `vX.Y.Z` | Fastlane uploads iOS build to TestFlight |

**Guards:**

- `pull_request_target` precautions so PRs from forks (if v2 goes open source) cannot run privileged jobs against the AWS account.
- GitHub Actions environment scoping (`dev`, `prod`) gates secret access; only the `main` workflow can read prod secrets.
- Branch protection on `main`: requires green CI, requires PR (even though solo — practice the discipline).
- `cdk diff` comment on every PR makes infra changes visible before merge.

**Path filters** keep CI fast:

- `api/**` and `shared/**` → backend tests + deploy `Api` stack
- `services/<name>/**` → that service's tests + deploy `<Name>` stack
- `web/**` → web tests + deploy `Web` stack
- `ios/**` → iOS build + tests (macOS runner)
- `infra/**` → full synth + diff + deploy of all touched stacks
- `shared/openapi/**` → regenerate client/server types, run consumer tests

## 8. Feature flags — AWS AppConfig

- One AppConfig application per environment: `caregiver-dev`, `caregiver-prod`.
- One configuration profile per app: a single JSON document with a schema validated at deploy time.
- Lambda extension layer on every function (in-process cache; default 45-second TTL).
- Web client fetches via `GET /flags` (small Lambda that returns flags evaluated for the current user/tenant).
- iOS client fetches via the same endpoint and caches per-session.

**Flag taxonomy:**

| Type | Purpose |
|---|---|
| Release flag | Gate a new feature during rollout. Naming: `feat_<area>_<feature>`. |
| Kill switch | Instantly disable a risky code path. Naming: `kill_<area>_<thing>`. |
| Experiment flag | Percentage rollout for A/B. Naming: `exp_<area>_<feature>`. |

**Every flag has an ADR** documenting purpose, default value, owner, and retirement criteria. Flags without a retirement plan are bugs.

## 9. Testing strategy — Trophy shape

| Layer | Tooling | When |
|---|---|---|
| Static analysis | TS strict mode, `golangci-lint`, Swift compiler, generated types from OpenAPI | Always, in CI |
| Integration | Go: `testing` + `testcontainers` for DynamoDB Local + LocalStack; TS: Vitest + MSW for components; Swift: XCTest with stubbed networking | Every PR |
| Unit | Reserved for non-trivial logic (date math, permission rules, flag evaluation) | As needed |
| E2E smoke | Playwright (web), `xcuitest` (iOS) — 1–3 critical flows per client | On prod deploy |

**TDD on the integration layer is encouraged** (per superpowers' `test-driven-development` skill). TDD on pure-orchestration code is not required.

**Coverage targets:** none specified (Goodhart's law). Rule of thumb: *"if this breaks in prod, did a test fail?" — if no, write the test.*

## 10. Decision tracking — MADR

- Location: `docs/adr/NNNN-kebab-title.md`.
- Format: MADR template (status, context, decision, consequences).
- Numbering: zero-padded (`0001-`), never reused; superseded records keep their number with status updated.
- One ADR per cross-cutting decision. Feature-scoped decisions stay in their spec's "Decisions" section.

**Seed ADRs** (to be written as part of F1 implementation):

| # | Title |
|---|---|
| 0001 | Parallel v2 over evolve-in-place |
| 0002 | Single monorepo over polyrepo |
| 0003 | OpenAPI 3 as contract source of truth |
| 0004 | Dev + prod environments; PR→dev, merge→prod |
| 0005 | AWS AppConfig for feature flags |
| 0006 | Testing trophy shape |
| 0007 | CloudWatch + X-Ray native observability with cost guardrails |
| 0008 | AWS CDK (TypeScript) for IaC |
| 0009 | Go backend, Next.js + React web, SwiftUI iOS |
| 0010 | AWS-native web hosting (CloudFront + S3 + Lambda SSR) |

## 11. Observability — CloudWatch + X-Ray with guardrails

**Logs:**
- Structured JSON via `slog` (Go) and `pino` (TS).
- Required fields on every line: `request_id`, `user_id`, `tenant_id`, `event`, `level`.
- Retention enforced in CDK: **7 days dev, 30 days prod**.

**Metrics:**
- Emitted via CloudWatch EMF (no PutMetricData calls).
- **Cap at ~8 custom metrics.** A new metric requires an ADR or a removal.
- **Forbidden dimension values:** anything high-cardinality (raw `user_id`, raw `tenant_id`, raw URL paths, raw error messages). High-cardinality values belong in logs and traces, never metric dimensions.
- **Allowed dimensions:** `service`, `env`, `path_template` (e.g., `/users/{id}`, not `/users/abc-123`), `status_class` (e.g., `2xx`, `5xx`), bucketed enums.

**Traces:**
- X-Ray enabled on every Lambda.
- 100% sampling until traffic exceeds free tier (100k traces/mo).

**Dashboards:**
- Maximum 2 (prod overview, dev overview). Defined in CDK, not hand-built in the console.
- Anything else is ad-hoc Logs Insights.

**Alarms:**
- ≤8 prod, ≤4 dev.
- Default set: 5xx rate, p95 latency, DynamoDB throttles, AppConfig fetch failures, DLQ depth.
- Alarm destinations: SNS topic → email.

**Cost tripwires:**
- CloudWatch billing alarm at $5/month.
- AWS Budgets alert at $20/month overall.

## 12. Infrastructure-as-code — AWS CDK (TypeScript)

- One CDK app, multiple stacks per environment.
- **Stack split:**
  - `shared-stack` — DynamoDB tables, SQS queues, SNS topics, AppConfig application/profile, KMS keys, alarm topic.
  - One stack per service (`api-stack`, `notifications-stack`, `email-stack`, `digest-stack`, `web-stack`).
  - Stack dependencies via stack references (CFN exports) or SSM Parameter Store.
- `cdk synth` runs in CI for type-safety.
- `cdk diff` posted as a PR comment.
- `cdk.context.json` checked into the repo (CDK's context cache).
- `cdk.json` defines per-environment context (account ID, region, log retention, etc.).

## 13. Languages, frameworks, and conventions

| Concern | Choice |
|---|---|
| Backend language | Go 1.23+ on Lambda `provided.al2` |
| Web framework | Next.js 15+ with React 19+, App Router |
| iOS | SwiftUI, minimum target iOS 17 |
| Web hosting | AWS-native: CloudFront + S3 (assets) + Lambda for SSR |
| Package management | Go modules; `pnpm` (TS); SPM (Swift) |
| Lint/format | `gofmt` + `golangci-lint`; Prettier + ESLint; SwiftFormat |
| Commits | Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`) |
| Branch protection | `main` requires PR + green CI |
| Pre-commit hooks | `pre-commit` framework runs format/lint locally |
| Dependency updates | Renovate (free, more flexible than Dependabot) |
| Secrets | SSM Parameter Store SecureString. **Default:** Lambda env vars resolved from SSM at deploy time (cheapest, simplest). **Exception:** rotation-sensitive secrets (DB passwords, third-party API keys with short TTLs) use the SSM Parameter Store Lambda extension for runtime fetch with caching. |

## 14. v1 → v2 directory mapping

| v1 | v2 |
|---|---|
| `care-giver-api` | `caregiver-v2/api/` |
| `care-giver-notification-orchestrator` | `caregiver-v2/services/notifications-orchestrator/` |
| `care-giver-notification-executor` | `caregiver-v2/services/notifications-executor/` |
| `care-giver-golang-common` | `caregiver-v2/shared/go-common/` |
| `care-giver-site` | `caregiver-v2/web/` |
| `care-giver-app-ios` | `caregiver-v2/ios/` |
| `care-giver-specs` | `caregiver-v2/docs/specs/` |

## 15. Implementation order (high level)

This will be elaborated in the F1 implementation plan, but the rough sequence:

1. Create `caregiver-v2/` monorepo skeleton, initialize git, push to GitHub.
2. Write seed ADRs 0001–0010 from this brainstorm.
3. CDK bootstrap, base `shared-stack` with empty placeholder resources.
4. Set up GitHub Actions: lint, build, test, `cdk synth`, `cdk diff` comment, dev deploy on PR, prod deploy on merge.
5. Set up branch protection on `main`.
6. Set up Renovate, pre-commit, Conventional Commits enforcement.
7. Establish OpenAPI codegen pipeline with a placeholder `health` endpoint to validate the full loop end-to-end.
8. Set up CloudWatch dashboards, alarms, billing tripwires.
9. Set up AppConfig application/profile per env; add a `flags_demo` flag and verify Lambda extension caching.
10. Write a runbook in `docs/` documenting the dev loop: how to add an endpoint, how to add a flag, how to add an ADR.

## 16. Open questions

- **Account topology.** This spec assumes single AWS account with stack-name separation for dev/prod. Is that the long-term plan, or should we move to dual accounts (dev account + prod account) later? Dual-account is the AWS best practice for isolation but adds setup overhead. Recommend deferring to a future ADR after F1 ships.
- **Web hosting details.** SSR-on-Lambda with Next.js works but requires care around the App Router / RSC pattern. The `@aws-sdk` integration for Next.js is improving but still has rough edges. May warrant its own mini-spec or ADR in C2.
- **Renovate config.** Default Renovate config is opinionated and noisy. We'll likely want a tuned config to batch updates and skip major bumps without review.

## 17. Risks

- **Solo dev complexity creep.** Every guardrail (branch protection, pre-commit, Conventional Commits, ADRs) adds friction. If F1 is too heavy, it slows the very iteration it's meant to accelerate. *Mitigation: revisit each convention after 1 month — drop what hasn't paid off.*
- **AppConfig misuse.** Feature flags accumulate. Without retirement discipline, the flag count grows unbounded. *Mitigation: ADR per flag with retirement criteria; quarterly flag-cleanup task.*
- **CloudWatch metric explosion.** EMF makes it easy to emit high-cardinality metrics by accident. *Mitigation: hard cap in the spec; review every new metric in PR.*
- **CDK lock-in.** Migrating away from CDK later is painful. *Mitigation: accept the lock-in. AWS-native is a stated goal.*

## 18. Success criteria

F1 is complete when:

- [ ] Monorepo exists, pushed to GitHub, branch-protected.
- [ ] CI runs on every PR: lint, type-check, build, test, `cdk synth`, `cdk diff` comment.
- [ ] `cdk deploy CaregiverDev` runs on PR; `cdk deploy CaregiverProd` runs on merge to `main`.
- [ ] OpenAPI codegen produces Go, TS, Swift types; a `/health` endpoint round-trips through generated code on both client and server.
- [ ] An AppConfig flag can be toggled in the console and a Lambda picks up the change within the cache TTL.
- [ ] CloudWatch dashboards and alarms exist and are wired to email.
- [ ] Billing alarm and AWS Budgets alert are armed.
- [ ] Seed ADRs 0001–0010 are written.
- [ ] A runbook explains how to add an endpoint, a flag, and an ADR.
