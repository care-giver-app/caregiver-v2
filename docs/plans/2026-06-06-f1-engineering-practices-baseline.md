# F1 — Engineering Practices Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the engineering rails for the Caregiver v2 monorepo: directory layout, contracts, CI/CD, feature flags, observability, decision tracking. Definition of done = spec §18 checklist.

**Architecture:** AWS-native monorepo. Go on Lambda, AWS CDK in TypeScript for IaC, OpenAPI 3 as contract source of truth, AppConfig for feature flags, CloudWatch + X-Ray for observability. PR opens → dev deploy; merge to `main` → prod deploy.

**Tech Stack:** Go 1.23+, TypeScript, AWS CDK 2.x, AWS Lambda (`provided.al2023`), API Gateway HTTP API, AppConfig, CloudWatch, X-Ray, GitHub Actions (OIDC to AWS), pnpm workspaces, Conventional Commits, MADR ADRs, Lefthook, Renovate.

**Spec:** `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`.

---

## Prerequisites (one-time, manual, before Task 1)

- [ ] AWS account exists; you have an admin IAM user/role for setup.
- [ ] AWS CLI v2 installed locally; `aws configure` complete; default region set to `us-east-2`.
- [ ] Node 20+, pnpm 9+, Go 1.23+, Xcode 16+, Docker (for testcontainers).
- [ ] GitHub account with permissions to create a repo and set branch protection.
- [ ] `gh` CLI installed and authenticated.

---

## Section 1 — Repository skeleton

### Task 1: Create monorepo directory structure

**Files:**

- Create: `api/`, `services/`, `shared/openapi/`, `shared/go-common/`, `shared/types-ts/`, `shared/types-go/`, `shared/types-swift/`, `web/`, `ios/`, `infra/`, `.github/workflows/`

Note: `docs/specs/` and `docs/adr/` already exist.

- [ ] **Step 1.1: Create the directories**

```bash
cd /Users/trevorwilliams/Code/CareGiverApp/caregiver-v2
mkdir -p api/cmd/lambda api/internal
mkdir -p services
mkdir -p shared/openapi shared/go-common shared/types-ts shared/types-go shared/types-swift
mkdir -p web ios infra/bin infra/lib infra/test
mkdir -p .github/workflows
```

- [ ] **Step 1.2: Add placeholder `.keep` files so empty directories survive git**

```bash
touch api/cmd/lambda/.keep api/internal/.keep services/.keep \
  shared/openapi/.keep shared/go-common/.keep shared/types-ts/.keep \
  shared/types-go/.keep shared/types-swift/.keep \
  web/.keep ios/.keep infra/bin/.keep infra/lib/.keep infra/test/.keep
```

- [ ] **Step 1.3: Verify structure**

Run: `ls -F` then `find . -type d -not -path '*/\.*' -not -path '*/node_modules*' | sort`

Expected output contains: `./api`, `./services`, `./shared`, `./web`, `./ios`, `./infra`, `./docs`, `./.github`.

---

### Task 2: Initialize git, add root `.gitignore`, `.editorconfig`, root `README.md`

**Files:**

- Create: `.gitignore`, `.editorconfig`, `README.md`

- [ ] **Step 2.1: `git init` and set default branch**

```bash
git init -b main
```

- [ ] **Step 2.2: Write `.gitignore`**

Create `.gitignore`:

```
# OS
.DS_Store
Thumbs.db

# Editors
.idea/
.vscode/
*.swp

# Node / pnpm
node_modules/
.pnpm-store/
*.tsbuildinfo
.next/
.turbo/

# Go
*.test
*.out
*.exe
bin/

# CDK
infra/cdk.out/
infra/.cdk.staging/

# Build artifacts
dist/
build/
coverage/
*.log

# Lambda
api/cmd/lambda/bootstrap
services/*/bootstrap

# Secrets / env
.env
.env.local
.env.*.local

# iOS
ios/build/
ios/DerivedData/
ios/*.xcuserdata/
ios/Pods/

# Lefthook
.lefthook/

# AWS
.aws-sam/
```

- [ ] **Step 2.3: Write `.editorconfig`**

Create `.editorconfig`:

```
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.go]
indent_style = tab

[*.{md,markdown}]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab
```

- [ ] **Step 2.4: Write root `README.md`**

Create `README.md`:

```markdown
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

See `docs/runbook.md` for the dev loop (added in F1's Task 41).

## Architecture

See `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`.
```

- [ ] **Step 2.5: Initial commit**

```bash
git add .gitignore .editorconfig README.md
git add api/.keep services/.keep shared/ web/.keep ios/.keep infra/ .github/
git commit -m "chore: initial monorepo skeleton"
```

Expected: one commit on `main`.

---

### Task 3: Set up pnpm workspace at root

**Files:**

- Create: `package.json`, `pnpm-workspace.yaml`, `.nvmrc`

- [ ] **Step 3.1: Add `.nvmrc`**

Create `.nvmrc`:

```
20
```

- [ ] **Step 3.2: Write root `package.json`**

Create `package.json`:

```json
{
  "name": "caregiver-v2",
  "version": "0.0.0",
  "private": true,
  "packageManager": "pnpm@9.12.0",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "lint": "pnpm -r run lint",
    "test": "pnpm -r run test",
    "build": "pnpm -r run build",
    "codegen": "pnpm --filter @caregiver/openapi run codegen"
  },
  "devDependencies": {
    "prettier": "^3.3.3"
  }
}
```

- [ ] **Step 3.3: Write `pnpm-workspace.yaml`**

Create `pnpm-workspace.yaml`:

```yaml
packages:
  - 'infra'
  - 'web'
  - 'shared/types-ts'
  - 'shared/openapi'
```

- [ ] **Step 3.4: Install root deps**

```bash
pnpm install
```

Expected: `node_modules/` populated, `pnpm-lock.yaml` created.

- [ ] **Step 3.5: Commit**

```bash
git add package.json pnpm-workspace.yaml pnpm-lock.yaml .nvmrc
git commit -m "chore: pnpm workspace + Node 20"
```

---

### Task 4: Set up Prettier at root

**Files:**

- Create: `.prettierrc.json`, `.prettierignore`

- [ ] **Step 4.1: Write `.prettierrc.json`**

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

- [ ] **Step 4.2: Write `.prettierignore`**

```
node_modules/
pnpm-lock.yaml
*.tsbuildinfo
.next/
dist/
build/
infra/cdk.out/
shared/types-ts/dist/
shared/types-go/
shared/types-swift/
*.go
*.swift
```

- [ ] **Step 4.3: Verify Prettier runs**

```bash
pnpm exec prettier --check "**/*.{ts,tsx,json,md,yaml,yml}"
```

Expected: passes on all current files (or list specific files needing format — apply with `--write` and re-run).

- [ ] **Step 4.4: Commit**

```bash
git add .prettierrc.json .prettierignore
git commit -m "chore: prettier config"
```

---

### Task 5: Set up Conventional Commits with commitlint + Lefthook

**Files:**

- Create: `commitlint.config.js`, `lefthook.yml`
- Modify: `package.json`

- [ ] **Step 5.1: Install commitlint and lefthook as devDependencies**

```bash
pnpm add -D -w @commitlint/cli @commitlint/config-conventional lefthook
```

- [ ] **Step 5.2: Write `commitlint.config.js`**

```js
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'docs', 'chore', 'refactor', 'test', 'perf', 'build', 'ci', 'revert'],
    ],
  },
};
```

- [ ] **Step 5.3: Write `lefthook.yml`**

```yaml
commit-msg:
  commands:
    commitlint:
      run: pnpm exec commitlint --edit {1}

pre-commit:
  parallel: true
  commands:
    prettier:
      glob: '**/*.{ts,tsx,js,jsx,json,md,yaml,yml}'
      run: pnpm exec prettier --check {staged_files}
```

- [ ] **Step 5.4: Install Lefthook hooks**

```bash
pnpm exec lefthook install
```

Expected: `.git/hooks/commit-msg` and `.git/hooks/pre-commit` now wired.

- [ ] **Step 5.5: Verify by attempting a bad commit message**

```bash
git commit --allow-empty -m "bad message"
```

Expected: FAILS with commitlint error ("type may not be empty").

- [ ] **Step 5.6: Verify by attempting a good commit message**

```bash
git commit --allow-empty -m "chore: verify commitlint"
```

Expected: PASSES.

- [ ] **Step 5.7: Commit the config**

```bash
git add commitlint.config.js lefthook.yml package.json pnpm-lock.yaml
git commit -m "chore: commitlint + lefthook for conventional commits"
```

---

### Task 6: Write seed ADRs 0001–0005

**Files:**

- Create: `docs/adr/0001-parallel-v2-over-evolve-in-place.md`, `0002-single-monorepo.md`, `0003-openapi-3-contract-source.md`, `0004-dev-prod-environments-pr-merge-triggers.md`, `0005-appconfig-feature-flags.md`

Each ADR uses MADR-lite format. Templates below — fill with the rationale we discussed.

- [ ] **Step 6.1: Create ADR template at `docs/adr/_template.md`**

```markdown
# NNNN — Title

- **Status:** Accepted
- **Date:** YYYY-MM-DD
- **Deciders:** Trevor Williams

## Context and Problem Statement

What is the issue or decision to be made?

## Considered Options

- Option A
- Option B
- Option C

## Decision

We chose Option X because...

## Consequences

### Positive

- ...

### Negative / Trade-offs

- ...

## Related

- Spec: `docs/specs/...`
- ADRs: ...
```

- [ ] **Step 6.2: Write ADR-0001 (Parallel v2 over evolve-in-place)**

Create `docs/adr/0001-parallel-v2-over-evolve-in-place.md`:

```markdown
# 0001 — Parallel v2 over Evolve-in-Place

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

V1 of the Caregiver app is a working personal project used by Trevor and his brothers. We want to rewrite it for multi-tenant use, custom event types, customizable dashboards, and an iOS-native client. The rewrite needs better engineering rails (CI/CD, feature flags, observability, ADRs). The question is whether to evolve v1 in place or build v2 in parallel.

## Considered Options

- **Parallel v2** — new repo, new backend, new clients. V1 keeps running for the family unchanged until v2 is ready.
- **Evolve in place** — refactor v1 incrementally behind feature flags toward the v2 design.
- **Hybrid** — new backend (clean break on contracts), evolve clients in place to point at the new backend.

## Decision

Parallel v2. The app is small, traffic is low (single family), and Trevor does not plan many updates to v1. The cost of maintaining both during the transition is minimal; the cost of evolving inside v1's choices (hard-coded event types, no multi-tenant model) is high.

## Consequences

### Positive

- Clean slate for data model, contracts, and engineering practices.
- No coexistence complexity in code.
- V1 remains a safety net for the family during the rebuild.

### Negative / Trade-offs

- Two deployments to monitor during the transition.
- Existing data will need a future migration story (deferred to a B4-style spec).

## Related

- Spec: `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md` §2
```

- [ ] **Step 6.3: Write ADR-0002 (Single monorepo)**

Create `docs/adr/0002-single-monorepo.md`:

```markdown
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
```

- [ ] **Step 6.4: Write ADR-0003 (OpenAPI 3 contract source)**

Create `docs/adr/0003-openapi-3-contract-source.md`:

```markdown
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
```

- [ ] **Step 6.5: Write ADR-0004 (Dev + prod environments with PR/merge triggers)**

Create `docs/adr/0004-dev-prod-environments-pr-merge-triggers.md`:

```markdown
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
```

- [ ] **Step 6.6: Write ADR-0005 (AppConfig for feature flags)**

Create `docs/adr/0005-appconfig-feature-flags.md`:

```markdown
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
```

- [ ] **Step 6.7: Commit ADRs 0001-0005**

```bash
git add docs/adr/
git commit -m "docs: seed ADRs 0001-0005"
```

---

### Task 7: Write seed ADRs 0006–0010

**Files:**

- Create: `docs/adr/0006-testing-trophy.md`, `0007-cloudwatch-xray-observability.md`, `0008-aws-cdk-typescript.md`, `0009-language-and-framework-choices.md`, `0010-aws-native-web-hosting.md`

- [ ] **Step 7.1: Write ADR-0006 (Testing trophy)**

Create `docs/adr/0006-testing-trophy.md`:

```markdown
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
```

- [ ] **Step 7.2: Write ADR-0007 (CloudWatch + X-Ray observability)**

Create `docs/adr/0007-cloudwatch-xray-observability.md`:

```markdown
# 0007 — CloudWatch + X-Ray Native Observability with Cost Guardrails

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

We need production logs, metrics, traces, and alerts. AWS-native is the cheapest and most transferable choice, but CloudWatch has been a surprise-bill source for Trevor in the past, so the choice needs explicit guardrails.

## Considered Options

- **CloudWatch + X-Ray native** — AWS-native, free tier covers our traffic if disciplined.
- **CloudWatch + managed APM (Datadog, Honeycomb)** — better UX, third-party cost.
- **Self-hosted (Grafana + Loki + Tempo)** — full control, ops burden.

## Decision

CloudWatch native + X-Ray with hard guardrails:

- ~8 custom metrics maximum (a new metric requires an ADR or a removal).
- No high-cardinality dimensions (user_id, raw paths, tenant_id raw).
- 2 dashboards max (prod + dev), defined in CDK.
- ≤8 prod alarms, ≤4 dev alarms.
- Log retention enforced in CDK: 7d dev, 30d prod.
- Billing alarm at $5/month CloudWatch, AWS Budgets at $20/month overall.

## Consequences

### Positive

- Cost is essentially $0 at our scale, with tripwires if that changes.
- Native to the rest of the stack; no extra egress or vendor dependency.

### Negative / Trade-offs

- CloudWatch UX is functional, not delightful.
- Discipline must be maintained as features grow.

## Related

- Spec: §11
```

- [ ] **Step 7.3: Write ADR-0008 (AWS CDK in TypeScript)**

Create `docs/adr/0008-aws-cdk-typescript.md`:

```markdown
# 0008 — AWS CDK in TypeScript for IaC

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

V1 uses SAM (YAML). For v2 we want IaC that scales with the stack as services are added, gives us type safety, and builds a more transferable skill than SAM.

## Considered Options

- **SAM** — AWS native, YAML, serverless-focused, what we know.
- **AWS CDK (TypeScript)** — programmatic IaC, type-safe, AWS-native.
- **Terraform** — cloud-agnostic, larger community, HCL.
- **SST** — opinionated framework on CDK.

## Decision

AWS CDK in TypeScript. One CDK app with multiple stacks per environment. Stack split: `shared-stack` (tables, queues, AppConfig), then one stack per service.

## Consequences

### Positive

- Real abstractions (Constructs) for reusable infra patterns.
- IDE autocomplete + type-checking on infra changes.
- Native AWS, first-party support.
- `cdk diff` shows clear infra deltas on every PR.

### Negative / Trade-offs

- Steeper learning curve than SAM YAML.
- CDK version upgrades occasionally require code changes.
- CDK output is CloudFormation; some edge cases hit CFN limits.

## Related

- Spec: §12
```

- [ ] **Step 7.4: Write ADR-0009 (Languages and frameworks)**

Create `docs/adr/0009-language-and-framework-choices.md`:

```markdown
# 0009 — Go Backend, Next.js + React Web, SwiftUI iOS

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

We need a backend language, web framework, and iOS framework for the v2 build. Choices weight cold-start performance (Lambda), solo-dev velocity, and transferable skills for Trevor's day job.

## Considered Options

- **A.** Stay with v1 stack: Go + Angular + SwiftUI.
- **B.** Modernize web only: Go + React/SvelteKit + SwiftUI.
- **C.** Full-stack TypeScript: Node + Next + SwiftUI.
- **D.** Go + SvelteKit + SwiftUI.

## Decision

Go for the backend (small Lambda binaries, fast cold start, existing skill), Next.js with React for the web (App Router, marketable React skill, AWS-friendly), SwiftUI for iOS (modern declarative, iOS 17+ minimum target).

## Consequences

### Positive

- Cold-start friendly Lambda (Go binaries are tiny on `provided.al2023`).
- React skill transferable to Trevor's day job.
- One frontend framework convention across web and iOS (declarative UI).

### Negative / Trade-offs

- Three languages to maintain in one repo.
- Cross-language test infra is more complex than full-stack TS would be.

## Related

- Spec: §13
```

- [ ] **Step 7.5: Write ADR-0010 (AWS-native web hosting)**

Create `docs/adr/0010-aws-native-web-hosting.md`:

```markdown
# 0010 — AWS-Native Web Hosting (CloudFront + S3 + Lambda for SSR)

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

Next.js can be hosted on Vercel (smooth DX) or AWS (more setup, single cloud, single bill). The "minimize cost" and "AWS-native" goals point one direction; the "fastest DX" goal points the other.

## Considered Options

- **Vercel** — best Next.js DX, external dependency.
- **Cloudflare Pages** — fast, external dependency.
- **AWS-native (CloudFront + S3 + Lambda for SSR)** — single cloud, single bill, more setup.

## Decision

AWS-native. Static assets in S3, served via CloudFront. SSR via Lambda (Function URL) or Lambda@Edge depending on which Next.js adapter we land on at C2 time.

## Consequences

### Positive

- Single AWS bill; cost stays bounded with our existing guardrails.
- IAM and Cognito integrations are natural.
- Skill applies to many AWS shops.

### Negative / Trade-offs

- Next.js + Lambda SSR is more setup than Vercel's drop-in deploy.
- The `@aws-sdk` / Next.js integration still has rough edges (will revisit at C2).

## Related

- Spec: §13
```

- [ ] **Step 7.6: Commit ADRs 0006-0010**

```bash
git add docs/adr/
git commit -m "docs: seed ADRs 0006-0010"
```

---

## Section 2 — Push to GitHub and protect main

### Task 8: Create GitHub repo and push initial commit

**Files:** none new

- [ ] **Step 8.1: Create the GitHub repo via `gh` (in the `care-giver-app` org)**

```bash
gh repo create care-giver-app/caregiver-v2 --private --source=. --remote=origin --description="Caregiver app v2 — multi-tenant rewrite"
```

Notes: the authenticated `gh` user must have permission to create repos in the `care-giver-app` org. If `gh` errors with a permissions message, run `gh auth refresh -h github.com -s admin:org` first.

Expected: `origin` set to `https://github.com/care-giver-app/caregiver-v2.git`.

- [ ] **Step 8.2: Push to main**

```bash
git push -u origin main
```

Expected: all current commits land on GitHub `main`.

- [ ] **Step 8.3: Verify in browser or `gh`**

```bash
gh repo view --web
```

Expected: repo opens; commits visible.

---

### Task 9: Configure branch protection on main

**Files:** none new (uses GitHub API via `gh`)

- [ ] **Step 9.1: Enable branch protection on `main`**

```bash
gh api -X PUT repos/:owner/:repo/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true,
  "required_conversation_resolution": true
}
EOF
```

Notes: `required_approving_review_count: 0` because solo dev can't approve own PRs; the discipline is requiring a PR at all. We'll add `required_status_checks` after CI exists (Task 17).

- [ ] **Step 9.2: Verify**

```bash
gh api repos/:owner/:repo/branches/main/protection | jq '.required_pull_request_reviews, .allow_force_pushes'
```

Expected: review settings present, force pushes disabled.

---

### Task 10: Configure GitHub OIDC for AWS (no long-lived keys)

**Files:**

- Create: `infra/lib/bootstrap-stack.ts` (later in Task 12); for now this task is AWS console + CLI setup.

- [ ] **Step 10.1: Create OIDC identity provider in AWS**

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Expected: ARN returned. Save it.

- [ ] **Step 10.2: Create IAM role for GitHub Actions to assume**

Replace `<ACCOUNT>` below with your 12-digit AWS account ID. The repo path is already pinned to `care-giver-app/caregiver-v2`.

Create `/tmp/gha-trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:care-giver-app/caregiver-v2:*"
        }
      }
    }
  ]
}
```

```bash
aws iam create-role --role-name CaregiverGitHubDeploy \
  --assume-role-policy-document file:///tmp/gha-trust-policy.json
```

- [ ] **Step 10.3: Attach an admin policy for now (we'll tighten after F1)**

```bash
aws iam attach-role-policy --role-name CaregiverGitHubDeploy \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Note: tightening to least-privilege is a follow-up ADR after F1 ships.

- [ ] **Step 10.4: Capture the role ARN as a GitHub repo secret**

```bash
ROLE_ARN=$(aws iam get-role --role-name CaregiverGitHubDeploy --query 'Role.Arn' --output text)
gh secret set AWS_DEPLOY_ROLE_ARN --body "$ROLE_ARN"
gh variable set AWS_REGION --body "us-east-2"
```

Expected: secret and variable set on the repo.

---

## Section 3 — CDK foundation

### Task 11: Scaffold the CDK app

**Files:**

- Create: `infra/package.json`, `infra/tsconfig.json`, `infra/cdk.json`, `infra/bin/app.ts`, `infra/jest.config.js`, `infra/test/.gitkeep`

- [ ] **Step 11.1: Add `infra/package.json`**

```json
{
  "name": "@caregiver/infra",
  "version": "0.0.0",
  "private": true,
  "bin": {
    "infra": "bin/app.js"
  },
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "test": "jest",
    "lint": "tsc --noEmit",
    "cdk": "cdk",
    "synth": "cdk synth",
    "diff": "cdk diff"
  },
  "devDependencies": {
    "@types/jest": "^29.5.13",
    "@types/node": "^20.16.5",
    "aws-cdk": "^2.163.1",
    "esbuild": "^0.24.0",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.5",
    "ts-node": "^10.9.2",
    "typescript": "^5.6.2"
  },
  "dependencies": {
    "aws-cdk-lib": "^2.163.1",
    "constructs": "^10.4.2"
  }
}
```

- [ ] **Step 11.2: Add `infra/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["es2022"],
    "declaration": true,
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "esModuleInterop": true,
    "experimentalDecorators": true,
    "resolveJsonModule": true,
    "outDir": "dist",
    "typeRoots": ["./node_modules/@types"]
  },
  "exclude": ["node_modules", "cdk.out", "dist"]
}
```

- [ ] **Step 11.3: Add `infra/cdk.json`**

```json
{
  "app": "npx ts-node --prefer-ts-exts bin/app.ts",
  "watch": {
    "include": ["**"],
    "exclude": [
      "README.md",
      "cdk*.json",
      "**/*.d.ts",
      "**/*.js",
      "tsconfig.json",
      "package*.json",
      "node_modules"
    ]
  },
  "context": {
    "@aws-cdk/aws-lambda:recognizeLayerVersion": true,
    "@aws-cdk/core:checkSecretUsage": true,
    "@aws-cdk/core:target-partitions": ["aws"],
    "@aws-cdk-containers/ecs-service-extensions:enableDefaultLogDriver": true,
    "@aws-cdk/aws-ec2:uniqueImdsv2TemplateName": true,
    "@aws-cdk/aws-iam:standardizedServicePrincipals": true,
    "@aws-cdk/core:newStyleStackSynthesis": true,
    "@aws-cdk/aws-rds:lowercaseDbIdentifier": true,
    "@aws-cdk/aws-route53-patters:useCertificate": true,
    "@aws-cdk/customresources:installLatestAwsSdkDefault": false,
    "@aws-cdk/aws-s3:autoDeleteObjectsRedirect": true
  }
}
```

- [ ] **Step 11.4: Add `infra/jest.config.js`**

```js
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['**/*.test.ts'],
  transform: {
    '^.+\\.tsx?$': 'ts-jest',
  },
};
```

- [ ] **Step 11.5: Add `infra/bin/app.ts` (entrypoint)**

```ts
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SharedStack } from '../lib/shared-stack';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION ?? 'us-east-2';
const env = { account, region };

const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';
if (stage !== 'dev' && stage !== 'prod') {
  throw new Error(`Invalid stage: ${stage}. Must be 'dev' or 'prod'.`);
}

const prefix = stage === 'prod' ? 'CaregiverProd' : 'CaregiverDev';

new SharedStack(app, `${prefix}-Shared`, { env, stage });
```

- [ ] **Step 11.6: Install infra deps**

```bash
cd infra
pnpm install
cd ..
```

Expected: `infra/node_modules/` populated.

- [ ] **Step 11.7: Commit**

```bash
git add infra/ pnpm-lock.yaml
git commit -m "chore(infra): scaffold CDK app"
```

---

### Task 12: Write shared-stack with test (TDD)

**Files:**

- Create: `infra/lib/shared-stack.ts`, `infra/test/shared-stack.test.ts`

- [ ] **Step 12.1: Write failing test first**

Create `infra/test/shared-stack.test.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { SharedStack } from '../lib/shared-stack';

describe('SharedStack', () => {
  test('dev stack creates an SNS topic for alarms', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'TestShared', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Caregiver Dev Alarms',
    });
  });

  test('prod stack uses prod alarm topic name', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'TestSharedProd', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'prod',
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Caregiver Prod Alarms',
    });
  });
});
```

- [ ] **Step 12.2: Run test, expect FAIL**

```bash
cd infra && pnpm test
```

Expected: FAIL (no `SharedStack` module yet).

- [ ] **Step 12.3: Write minimal `shared-stack.ts`**

Create `infra/lib/shared-stack.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';

export type Stage = 'dev' | 'prod';

export interface SharedStackProps extends cdk.StackProps {
  stage: Stage;
}

export class SharedStack extends cdk.Stack {
  public readonly alarmTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: SharedStackProps) {
    super(scope, id, props);

    const stageLabel = props.stage === 'prod' ? 'Prod' : 'Dev';

    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `caregiver-${props.stage}-alarms`,
      displayName: `Caregiver ${stageLabel} Alarms`,
    });

    cdk.Tags.of(this).add('Project', 'Caregiver');
    cdk.Tags.of(this).add('Stage', props.stage);
  }
}
```

- [ ] **Step 12.4: Run test, expect PASS**

```bash
cd infra && pnpm test
```

Expected: PASS (2 tests).

- [ ] **Step 12.5: Run `cdk synth` to validate**

```bash
cd infra && pnpm exec cdk synth
```

Expected: a CloudFormation template prints; no errors.

- [ ] **Step 12.6: Commit**

```bash
git add infra/lib/ infra/test/
git commit -m "feat(infra): shared-stack with alarm SNS topic"
```

---

### Task 13: CDK bootstrap and first dev deploy as smoke test

**Files:** none new (AWS-side bootstrap)

- [ ] **Step 13.1: Bootstrap CDK in the account/region**

```bash
cd infra && pnpm exec cdk bootstrap aws://658340567265/us-east-2
```

Expected: `CDKToolkit` stack created in AWS.

- [ ] **Step 13.2: Deploy dev shared-stack locally as a smoke test**

```bash
cd infra && pnpm exec cdk deploy CaregiverDev-Shared --require-approval never
```

Expected: stack creates successfully; `CaregiverDev-Shared` shows in CloudFormation console with the SNS topic.

- [ ] **Step 13.3: Verify the SNS topic exists**

```bash
aws sns list-topics | grep caregiver-dev-alarms
```

Expected: topic ARN returned.

- [ ] **Step 13.4: Subscribe your email to the dev alarm topic**

```bash
aws sns subscribe \
  --topic-arn $(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':caregiver-dev-alarms')].TopicArn" --output text) \
  --protocol email \
  --notification-endpoint <YOUR_EMAIL>
```

Then confirm the subscription via the email link.

Expected: subscription `PendingConfirmation` → `Confirmed` after clicking the email.

---

## Section 4 — First CI workflow

### Task 14: GitHub Actions — Lint + TypeScript checks on PR

**Files:**

- Create: `.github/workflows/ci-pr.yml`

- [ ] **Step 14.1: Write `ci-pr.yml`**

Create `.github/workflows/ci-pr.yml`:

```yaml
name: ci-pr

on:
  pull_request:
    branches: [main]

concurrency:
  group: ci-pr-${{ github.head_ref }}
  cancel-in-progress: true

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  lint:
    name: Lint + TS check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        # Version comes from package.json `packageManager` field — do NOT add `with: version`.
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - name: Prettier check
        run: pnpm exec prettier --check "**/*.{ts,tsx,json,md,yaml,yml}"
      - name: TypeScript build (infra)
        run: pnpm --filter @caregiver/infra run build

  go-lint-test:
    name: Go lint + test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'
          cache: true
      - name: Verify Go modules exist
        run: |
          if find . -name 'go.mod' -not -path './node_modules/*' | grep -q .; then
            echo "Go modules found"
          else
            echo "No Go modules yet (skipping)"
          fi
      - name: golangci-lint
        if: hashFiles('**/go.mod') != ''
        uses: golangci/golangci-lint-action@v6
        with:
          version: v1.61
      - name: go test
        if: hashFiles('**/go.mod') != ''
        run: |
          for dir in $(find . -name go.mod -not -path './node_modules/*' -exec dirname {} \;); do
            (cd "$dir" && go test ./...)
          done
```

- [ ] **Step 14.2: Open a PR with this workflow**

```bash
git checkout -b chore/initial-ci
git add .github/workflows/ci-pr.yml
git commit -m "ci: lint + build on PR"
git push -u origin chore/initial-ci
gh pr create --title "ci: lint + build on PR" --body "Initial CI workflow." --base main
```

- [ ] **Step 14.3: Verify CI runs and passes**

```bash
gh pr checks
```

Expected: `lint` and `go-lint-test` jobs PASS.

- [ ] **Step 14.4: Merge the PR**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
```

Expected: PR squash-merged; local `main` up to date.

---

### Task 15: GitHub Actions — `cdk synth` + diff comment on PR

**Files:**

- Modify: `.github/workflows/ci-pr.yml` (add new job)

- [ ] **Step 15.1: Branch and add `cdk-diff` job to `ci-pr.yml`**

```bash
git checkout -b ci/cdk-diff
```

Add this job to `.github/workflows/ci-pr.yml`:

```yaml
cdk-diff:
  name: CDK synth + diff
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
      # Version comes from package.json `packageManager` field — do NOT add `with: version`.
    - uses: actions/setup-node@v4
      with:
        node-version-file: .nvmrc
        cache: pnpm
    - uses: actions/setup-go@v5
      with:
        go-version: '1.23'
        cache: true
    - run: pnpm install --frozen-lockfile
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
        aws-region: ${{ vars.AWS_REGION }}
    - name: CDK synth
      run: pnpm --filter @caregiver/infra exec cdk synth --context stage=dev
    - name: CDK diff
      id: cdk-diff
      run: |
        set +e
        pnpm --filter @caregiver/infra exec cdk diff --context stage=dev > /tmp/cdk-diff.txt 2>&1
        echo "exit_code=$?" >> "$GITHUB_OUTPUT"
        cat /tmp/cdk-diff.txt
    - name: Post diff as PR comment
      uses: actions/github-script@v7
      with:
        script: |
          const fs = require('fs');
          const diff = fs.readFileSync('/tmp/cdk-diff.txt', 'utf8');
          const body = `### CDK diff (dev)\n\n\`\`\`\n${diff.slice(0, 60000)}\n\`\`\``;
          const { data: comments } = await github.rest.issues.listComments({
            ...context.repo,
            issue_number: context.issue.number,
          });
          const existing = comments.find(c => c.user.type === 'Bot' && c.body.startsWith('### CDK diff'));
          if (existing) {
            await github.rest.issues.updateComment({
              ...context.repo,
              comment_id: existing.id,
              body,
            });
          } else {
            await github.rest.issues.createComment({
              ...context.repo,
              issue_number: context.issue.number,
              body,
            });
          }
```

- [ ] **Step 15.2: Open a PR and verify the diff comment posts**

```bash
git add .github/workflows/ci-pr.yml
git commit -m "ci: cdk synth + diff comment on PR"
git push -u origin ci/cdk-diff
gh pr create --title "ci: cdk synth + diff comment" --body "Adds cdk synth + diff job." --base main
```

Watch the PR check; expected: `cdk-diff` job runs, comment appears showing the diff against the current dev stack.

- [ ] **Step 15.3: Merge**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
```

---

### Task 16: GitHub Actions — Deploy to dev on PR

**Files:**

- Modify: `.github/workflows/ci-pr.yml` (add deploy job)

- [ ] **Step 16.1: Branch**

```bash
git checkout -b ci/deploy-dev
```

- [ ] **Step 16.2: Add `deploy-dev` job that depends on `cdk-diff`**

Add to `.github/workflows/ci-pr.yml`:

```yaml
deploy-dev:
  name: Deploy to dev
  needs: [lint, cdk-diff]
  if: github.event.pull_request.head.repo.full_name == github.repository
  runs-on: ubuntu-latest
  concurrency:
    group: deploy-dev
    cancel-in-progress: false
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
      # Version comes from package.json `packageManager` field — do NOT add `with: version`.
    - uses: actions/setup-node@v4
      with:
        node-version-file: .nvmrc
        cache: pnpm
    - uses: actions/setup-go@v5
      with:
        go-version: '1.23'
        cache: true
    - run: pnpm install --frozen-lockfile
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
        aws-region: ${{ vars.AWS_REGION }}
    - name: CDK deploy dev
      run: pnpm --filter @caregiver/infra exec cdk deploy --all --context stage=dev --require-approval never
```

Notes:

- `if: github.event.pull_request.head.repo.full_name == github.repository` blocks deploys from forks.
- `concurrency: deploy-dev` serializes deploys so two PRs don't race.

- [ ] **Step 16.3: Open PR, watch deploy job**

```bash
git add .github/workflows/ci-pr.yml
git commit -m "ci: deploy to dev on PR"
git push -u origin ci/deploy-dev
gh pr create --title "ci: deploy to dev on PR" --body "Adds deploy-dev job." --base main
gh pr checks --watch
```

Expected: `deploy-dev` job deploys `CaregiverDev-Shared`. CloudFormation shows stack `UPDATE_COMPLETE` (or no change).

- [ ] **Step 16.4: Merge**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
```

---

### Task 17: GitHub Actions — Deploy to prod on merge to main

**Files:**

- Create: `.github/workflows/cd-main.yml`

- [ ] **Step 17.1: Branch and write workflow**

```bash
git checkout -b ci/deploy-prod
```

Create `.github/workflows/cd-main.yml`:

```yaml
name: cd-main

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

concurrency:
  group: deploy-prod
  cancel-in-progress: false

jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        # Version comes from package.json `packageManager` field — do NOT add `with: version`.
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'
          cache: true
      - run: pnpm install --frozen-lockfile
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - name: Run all tests
        run: |
          pnpm --filter @caregiver/infra run test
          for dir in $(find . -name go.mod -not -path './node_modules/*' -exec dirname {} \;); do
            (cd "$dir" && go test ./...)
          done
      - name: CDK deploy prod
        run: pnpm --filter @caregiver/infra exec cdk deploy --all --context stage=prod --require-approval never
```

- [ ] **Step 17.2: Open PR**

```bash
git add .github/workflows/cd-main.yml
git commit -m "ci: deploy to prod on merge to main"
git push -u origin ci/deploy-prod
gh pr create --title "ci: deploy to prod on merge to main" --body "Adds prod CD workflow." --base main
```

- [ ] **Step 17.3: Merge and watch prod deploy run**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
gh run watch
```

Expected: `cd-main` workflow runs, deploys `CaregiverProd-Shared`. The prod SNS alarm topic appears in the prod stack.

- [ ] **Step 17.4: Subscribe email to the prod alarm topic**

```bash
aws sns subscribe \
  --topic-arn $(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':caregiver-prod-alarms')].TopicArn" --output text) \
  --protocol email \
  --notification-endpoint <YOUR_EMAIL>
```

Confirm the email subscription.

- [ ] **Step 17.5: Add required status checks to branch protection**

Now that CI exists, update branch protection to require it:

```bash
gh api -X PUT repos/:owner/:repo/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["lint", "go-lint-test", "cdk-diff", "deploy-dev"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true,
  "required_conversation_resolution": true
}
EOF
```

Expected: future PRs require those four checks to pass before merge.

---

## Section 5 — OpenAPI source and codegen

### Task 18: Create `openapi.yaml` with `/health`

**Files:**

- Create: `shared/openapi/package.json`, `shared/openapi/openapi.yaml`

- [ ] **Step 18.1: Branch**

```bash
git checkout -b feat/openapi-health
```

- [ ] **Step 18.2: Add `shared/openapi/package.json`**

```json
{
  "name": "@caregiver/openapi",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "lint": "redocly lint openapi.yaml",
    "codegen": "echo 'See Tasks 19-21 for language-specific codegen.'",
    "test": "echo 'no tests'"
  },
  "devDependencies": {
    "@redocly/cli": "^1.25.0"
  }
}
```

- [ ] **Step 18.3: Add `shared/openapi/openapi.yaml`**

```yaml
openapi: 3.0.3
info:
  title: Caregiver API
  version: 0.1.0
  description: Caregiver v2 API contract — source of truth.
servers:
  - url: https://api.dev.example.com
    description: dev
  - url: https://api.example.com
    description: prod
paths:
  /health:
    get:
      operationId: getHealth
      summary: Health check
      description: Returns service health and build metadata.
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Health'
components:
  schemas:
    Health:
      type: object
      required: [status, version, timestamp]
      properties:
        status:
          type: string
          enum: [ok, degraded]
        version:
          type: string
          example: '0.1.0'
        timestamp:
          type: string
          format: date-time
```

- [ ] **Step 18.4: Install Redocly CLI**

```bash
pnpm install
```

- [ ] **Step 18.5: Lint the spec**

```bash
pnpm --filter @caregiver/openapi run lint
```

Expected: passes.

- [ ] **Step 18.6: Commit**

```bash
git add shared/openapi/ pnpm-workspace.yaml pnpm-lock.yaml
git commit -m "feat(openapi): add /health endpoint to contract"
```

---

### Task 19: Go server codegen with `oapi-codegen`

**Files:**

- Create: `shared/types-go/go.mod`, `shared/types-go/tools.go`, `shared/types-go/Makefile`, `shared/types-go/oapi-config.yaml`
- Update: `pnpm-workspace.yaml` is fine; Go is outside pnpm.

- [ ] **Step 19.1: Initialize a Go module for the generated types**

```bash
cd shared/types-go
go mod init github.com/care-giver-app/caregiver-v2/shared/types-go
```

- [ ] **Step 19.2: Add `oapi-config.yaml`**

```yaml
package: caregiverapi
output: ./caregiverapi/types.gen.go
generate:
  models: true
  embedded-spec: true
  strict-server: true
  chi-server: false
  std-http-server: true
```

- [ ] **Step 19.3: Add `tools.go` to pin codegen tool**

```go
//go:build tools
// +build tools

package tools

import (
	_ "github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen"
)
```

- [ ] **Step 19.4: Add `Makefile`**

```makefile
.PHONY: codegen test

OPENAPI := ../openapi/openapi.yaml

codegen:
	mkdir -p caregiverapi
	go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen -config oapi-config.yaml $(OPENAPI)

test:
	go test ./...
```

- [ ] **Step 19.5: Fetch deps and run codegen**

```bash
cd shared/types-go
go mod tidy
make codegen
```

Expected: `shared/types-go/caregiverapi/types.gen.go` created; compiles.

- [ ] **Step 19.6: Verify it compiles**

```bash
cd shared/types-go && go build ./...
```

Expected: no errors.

- [ ] **Step 19.7: Commit**

```bash
git add shared/types-go/
git commit -m "feat(types-go): generated Go server stubs for /health"
```

---

### Task 20: TS client codegen with `openapi-typescript` + `openapi-fetch`

**Files:**

- Create: `shared/types-ts/package.json`, `shared/types-ts/tsconfig.json`, `shared/types-ts/src/client.ts`

- [ ] **Step 20.1: Add `shared/types-ts/package.json`**

```json
{
  "name": "@caregiver/types-ts",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "main": "./dist/client.js",
  "types": "./dist/client.d.ts",
  "exports": {
    ".": {
      "types": "./dist/client.d.ts",
      "import": "./dist/client.js"
    }
  },
  "scripts": {
    "codegen": "openapi-typescript ../openapi/openapi.yaml -o src/schema.gen.ts",
    "build": "pnpm codegen && tsc",
    "test": "echo 'no tests'",
    "lint": "echo 'no lint'"
  },
  "dependencies": {
    "openapi-fetch": "^0.13.0"
  },
  "devDependencies": {
    "openapi-typescript": "^7.4.1",
    "typescript": "^5.6.2"
  }
}
```

- [ ] **Step 20.2: Add `shared/types-ts/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "declaration": true,
    "outDir": "dist",
    "rootDir": "src",
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts"]
}
```

- [ ] **Step 20.3: Add `shared/types-ts/src/client.ts`**

```ts
import createClient from 'openapi-fetch';
import type { paths } from './schema.gen';

export function makeClient(baseUrl: string) {
  return createClient<paths>({ baseUrl });
}

export type { paths } from './schema.gen';
```

- [ ] **Step 20.4: Add `shared/types-ts/` to pnpm-workspace.yaml** (already there from Task 3)

Verify `pnpm-workspace.yaml` lists `shared/types-ts`. If not, add it.

- [ ] **Step 20.5: Install + build**

```bash
pnpm install
pnpm --filter @caregiver/types-ts run build
```

Expected: `shared/types-ts/dist/` populated with `client.js`, `client.d.ts`, `schema.gen.js`, `schema.gen.d.ts`.

- [ ] **Step 20.6: Commit**

```bash
git add shared/types-ts/
git commit -m "feat(types-ts): generated TS client for /health"
```

---

### Task 21: Swift client codegen with `swift-openapi-generator`

**Files:**

- Create: `shared/types-swift/Package.swift`, `shared/types-swift/Sources/CaregiverAPI/Empty.swift`, `shared/types-swift/openapi-generator-config.yaml`, copy of `openapi.yaml` symlink

- [ ] **Step 21.1: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CaregiverAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CaregiverAPI", targets: ["CaregiverAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.2"),
    ],
    targets: [
        .target(
            name: "CaregiverAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            resources: [
                .copy("openapi.yaml"),
                .copy("openapi-generator-config.yaml"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
    ]
)
```

- [ ] **Step 21.2: Create generator config**

Create `shared/types-swift/Sources/CaregiverAPI/openapi-generator-config.yaml`:

```yaml
generate:
  - types
  - client
accessModifier: public
namingStrategy: idiomatic
```

- [ ] **Step 21.3: Copy `openapi.yaml` into the Swift package's resources**

```bash
cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
```

Note: SPM resource plugins don't follow symlinks reliably in CI; copy is safer. We'll automate the copy in CI (Task 22).

- [ ] **Step 21.4: Add a stub Swift file so the target compiles**

Create `shared/types-swift/Sources/CaregiverAPI/Empty.swift`:

```swift
// Placeholder so the target compiles. Generated types appear at build time
// via the OpenAPIGenerator plugin.
import Foundation
```

- [ ] **Step 21.5: Build the package (requires Swift toolchain on macOS)**

```bash
cd shared/types-swift && swift build
```

Expected: build completes; generated Swift types appear in DerivedData.

- [ ] **Step 21.6: Commit**

```bash
git add shared/types-swift/
git commit -m "feat(types-swift): swift-openapi-generator package for /health"
```

---

### Task 22: Wire codegen into CI and pre-commit

**Files:**

- Modify: `.github/workflows/ci-pr.yml`, `lefthook.yml`

- [ ] **Step 22.1: Add a `codegen-check` job to `ci-pr.yml`**

This job regenerates the Go and TS clients and fails if anything has drifted from what's committed.

Add to `.github/workflows/ci-pr.yml`:

```yaml
codegen-check:
  name: Codegen drift check
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
      # Version comes from package.json `packageManager` field — do NOT add `with: version`.
    - uses: actions/setup-node@v4
      with:
        node-version-file: .nvmrc
        cache: pnpm
    - uses: actions/setup-go@v5
      with:
        go-version: '1.23'
        cache: true
    - run: pnpm install --frozen-lockfile
    - name: Regenerate TS client
      run: pnpm --filter @caregiver/types-ts run build
    - name: Regenerate Go server stubs
      run: |
        cd shared/types-go
        go mod tidy
        make codegen
    - name: Copy openapi.yaml into Swift resources
      run: cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
    - name: Fail if anything changed
      run: |
        git status --porcelain
        if [ -n "$(git status --porcelain)" ]; then
          echo "::error::Generated files are out of date. Re-run codegen locally."
          git diff
          exit 1
        fi
```

- [ ] **Step 22.2: Add a pre-commit hook to regenerate when `openapi.yaml` changes**

Modify `lefthook.yml`:

```yaml
commit-msg:
  commands:
    commitlint:
      run: pnpm exec commitlint --edit {1}

pre-commit:
  parallel: true
  commands:
    prettier:
      glob: '**/*.{ts,tsx,js,jsx,json,md,yaml,yml}'
      run: pnpm exec prettier --check {staged_files}
    openapi-codegen:
      glob: 'shared/openapi/openapi.yaml'
      run: |
        pnpm --filter @caregiver/types-ts run build
        (cd shared/types-go && make codegen)
        cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
        git add shared/types-ts shared/types-go shared/types-swift
```

- [ ] **Step 22.3: Commit and PR**

```bash
git add .github/workflows/ci-pr.yml lefthook.yml
git commit -m "ci: codegen drift check + pre-commit regen on openapi changes"
git push -u origin feat/openapi-health
gh pr create --title "feat: openapi /health + codegen pipeline" --body "Adds OpenAPI source, Go/TS/Swift codegen, CI drift check, pre-commit regen." --base main
gh pr checks --watch
```

Expected: all checks pass.

- [ ] **Step 22.4: Merge**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
```

---

## Section 6 — `/health` Lambda + API stack

### Task 23: Create `shared/go-common` with logger and config

**Files:**

- Create: `shared/go-common/go.mod`, `shared/go-common/logger/logger.go`, `shared/go-common/logger/logger_test.go`, `shared/go-common/config/config.go`

- [ ] **Step 23.1: Branch and init module**

```bash
git checkout -b feat/health-lambda
mkdir -p shared/go-common/logger shared/go-common/config
cd shared/go-common
go mod init github.com/care-giver-app/caregiver-v2/shared/go-common
cd -
```

- [ ] **Step 23.2: Write the logger test (fails first)**

Create `shared/go-common/logger/logger_test.go`:

```go
package logger

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestNewProducesJSON(t *testing.T) {
	var buf bytes.Buffer
	log := NewWithWriter(&buf, "test-service", "dev")
	log.Info("hello", "k", "v")

	line := strings.TrimSpace(buf.String())
	var got map[string]any
	if err := json.Unmarshal([]byte(line), &got); err != nil {
		t.Fatalf("not valid JSON: %v\nline: %s", err, line)
	}
	if got["msg"] != "hello" {
		t.Errorf("expected msg=hello, got %v", got["msg"])
	}
	if got["service"] != "test-service" {
		t.Errorf("expected service=test-service, got %v", got["service"])
	}
	if got["env"] != "dev" {
		t.Errorf("expected env=dev, got %v", got["env"])
	}
	if got["k"] != "v" {
		t.Errorf("expected k=v, got %v", got["k"])
	}
}
```

- [ ] **Step 23.3: Run test, expect FAIL**

```bash
cd shared/go-common && go test ./logger
```

Expected: FAIL (no package).

- [ ] **Step 23.4: Implement `logger.go`**

Create `shared/go-common/logger/logger.go`:

```go
// Package logger wraps slog with the structured fields required across all
// Caregiver services: service, env. Per-request fields (request_id, user_id,
// tenant_id) are attached at handler boundaries.
package logger

import (
	"io"
	"log/slog"
	"os"
)

// New returns a JSON logger writing to stdout.
func New(service, env string) *slog.Logger {
	return NewWithWriter(os.Stdout, service, env)
}

// NewWithWriter is the same as New but writes to the provided writer.
// Used by tests.
func NewWithWriter(w io.Writer, service, env string) *slog.Logger {
	h := slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})
	return slog.New(h).With("service", service, "env", env)
}
```

- [ ] **Step 23.5: Run test, expect PASS**

```bash
cd shared/go-common && go test ./logger
```

Expected: PASS.

- [ ] **Step 23.6: Add `config/config.go`**

Create `shared/go-common/config/config.go`:

```go
// Package config centralizes environment-variable parsing so handlers don't
// scatter os.Getenv calls.
package config

import (
	"fmt"
	"os"
)

type Config struct {
	Service string
	Stage   string
	Version string
}

// FromEnv reads required configuration from environment variables.
// SERVICE, STAGE, and APP_VERSION are required.
func FromEnv() (Config, error) {
	c := Config{
		Service: os.Getenv("SERVICE"),
		Stage:   os.Getenv("STAGE"),
		Version: os.Getenv("APP_VERSION"),
	}
	if c.Service == "" || c.Stage == "" || c.Version == "" {
		return c, fmt.Errorf("missing required env: SERVICE=%q STAGE=%q APP_VERSION=%q",
			c.Service, c.Stage, c.Version)
	}
	return c, nil
}
```

- [ ] **Step 23.7: Tidy and commit**

```bash
cd shared/go-common && go mod tidy && cd -
git add shared/go-common/
git commit -m "feat(go-common): structured logger + config"
```

---

### Task 24: Write the `/health` Lambda handler (TDD)

**Files:**

- Create: `api/go.mod`, `api/internal/handlers/health.go`, `api/internal/handlers/health_test.go`, `api/cmd/lambda/main.go`

- [ ] **Step 24.1: Init API Go module**

```bash
cd api
go mod init github.com/care-giver-app/caregiver-v2/api
cd -
```

- [ ] **Step 24.2: Write the failing handler test**

Create `api/internal/handlers/health_test.go`:

```go
package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHealthHandler_ReturnsOK(t *testing.T) {
	h := NewHealth("0.1.0", func() time.Time { return time.Date(2026, 6, 6, 12, 0, 0, 0, time.UTC) })

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("invalid JSON body: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("expected status=ok, got %s", body["status"])
	}
	if body["version"] != "0.1.0" {
		t.Errorf("expected version=0.1.0, got %s", body["version"])
	}
	if body["timestamp"] != "2026-06-06T12:00:00Z" {
		t.Errorf("expected timestamp=2026-06-06T12:00:00Z, got %s", body["timestamp"])
	}
}
```

- [ ] **Step 24.3: Run test, expect FAIL**

```bash
cd api && go test ./...
```

Expected: FAIL (no `handlers` package).

- [ ] **Step 24.4: Implement `health.go`**

Create `api/internal/handlers/health.go`:

```go
package handlers

import (
	"encoding/json"
	"net/http"
	"time"
)

type Health struct {
	version string
	now     func() time.Time
}

func NewHealth(version string, now func() time.Time) *Health {
	if now == nil {
		now = time.Now
	}
	return &Health{version: version, now: now}
}

func (h *Health) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	resp := map[string]string{
		"status":    "ok",
		"version":   h.version,
		"timestamp": h.now().UTC().Format(time.RFC3339),
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
```

- [ ] **Step 24.5: Run test, expect PASS**

```bash
cd api && go test ./...
```

Expected: PASS.

- [ ] **Step 24.6: Write the Lambda entrypoint**

Create `api/cmd/lambda/main.go`:

```go
package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

func main() {
	cfg, err := config.FromEnv()
	if err != nil {
		// Fall back to plain stderr because logger requires config.
		slog.New(slog.NewJSONHandler(os.Stderr, nil)).Error("config error", "err", err)
		os.Exit(1)
	}

	log := logger.New(cfg.Service, cfg.Stage)
	log.Info("starting", "version", cfg.Version)

	mux := newMux(cfg)
	adapter := httpadapter.NewV2(mux)

	lambda.Start(func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		return adapter.ProxyWithContext(ctx, req)
	})
}
```

Create `api/cmd/lambda/mux.go`:

```go
package main

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
)

func newMux(cfg config.Config) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))
	return mux
}
```

- [ ] **Step 24.7: Add `replace` directive so api/ uses local shared module**

In `api/go.mod`, add:

```
replace github.com/care-giver-app/caregiver-v2/shared/go-common => ../shared/go-common
```

Then:

```bash
cd api && go mod tidy && cd -
```

- [ ] **Step 24.8: Build the bootstrap binary locally to validate**

```bash
cd api/cmd/lambda
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap ./...
file bootstrap
rm bootstrap
cd -
```

Expected: produces an ELF Linux ARM64 binary, then removes it (we don't commit binaries).

- [ ] **Step 24.9: Commit**

```bash
git add api/
git commit -m "feat(api): /health lambda handler with TDD"
```

---

### Task 25: Build the API stack in CDK

**Files:**

- Create: `infra/lib/api-stack.ts`, `infra/test/api-stack.test.ts`
- Modify: `infra/bin/app.ts`, `infra/package.json` (add aws-cdk-lib already present + esbuild for bundling)

- [ ] **Step 25.1: Write the failing API stack test**

Create `infra/test/api-stack.test.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { ApiStack } from '../lib/api-stack';

describe('ApiStack', () => {
  test('creates a Lambda function and HTTP API', () => {
    const app = new cdk.App();
    const stack = new ApiStack(app, 'TestApi', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
      version: '0.0.0-test',
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'provided.al2023',
      Architectures: ['arm64'],
      TracingConfig: { Mode: 'Active' },
    });
    template.resourceCountIs('AWS::ApiGatewayV2::Api', 1);
    template.resourceCountIs('AWS::ApiGatewayV2::Route', 1);
  });
});
```

- [ ] **Step 25.2: Run test, expect FAIL**

```bash
cd infra && pnpm test
```

Expected: FAIL (no `ApiStack`).

- [ ] **Step 25.3: Write `api-stack.ts`**

Create `infra/lib/api-stack.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigw from 'aws-cdk-lib/aws-apigatewayv2';
import * as integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'node:path';
import { execSync } from 'node:child_process';
import type { Stage } from './shared-stack';

export interface ApiStackProps extends cdk.StackProps {
  stage: Stage;
  version: string;
}

export class ApiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    const apiRoot = path.resolve(__dirname, '..', '..', 'api');
    const bootstrapDir = path.resolve(apiRoot, 'cmd', 'lambda');

    // Build the Go Lambda binary at synth time. CDK calls cdk.AssetStaging
    // for the directory once we declare it.
    execSync(
      'GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap ./...',
      { cwd: bootstrapDir, stdio: 'inherit' },
    );

    const fn = new lambda.Function(this, 'ApiFunction', {
      runtime: lambda.Runtime.PROVIDED_AL2023,
      architecture: lambda.Architecture.ARM_64,
      handler: 'bootstrap',
      code: lambda.Code.fromAsset(bootstrapDir, {
        exclude: ['*.go', '*.mod', '*.sum'],
      }),
      memorySize: 256,
      timeout: cdk.Duration.seconds(10),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        SERVICE: 'api',
        STAGE: props.stage,
        APP_VERSION: props.version,
      },
      logRetention:
        props.stage === 'prod' ? logs.RetentionDays.ONE_MONTH : logs.RetentionDays.ONE_WEEK,
    });

    const httpApi = new apigw.HttpApi(this, 'HttpApi', {
      apiName: `caregiver-${props.stage}-api`,
    });

    httpApi.addRoutes({
      path: '/health',
      methods: [apigw.HttpMethod.GET],
      integration: new integ.HttpLambdaIntegration('HealthIntegration', fn),
    });

    new cdk.CfnOutput(this, 'HttpApiUrl', { value: httpApi.apiEndpoint });
  }
}
```

- [ ] **Step 25.4: Update `bin/app.ts` to wire the stack**

Modify `infra/bin/app.ts`:

```ts
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SharedStack } from '../lib/shared-stack';
import { ApiStack } from '../lib/api-stack';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION ?? 'us-east-2';
const env = { account, region };

const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';
if (stage !== 'dev' && stage !== 'prod') {
  throw new Error(`Invalid stage: ${stage}. Must be 'dev' or 'prod'.`);
}

const prefix = stage === 'prod' ? 'CaregiverProd' : 'CaregiverDev';
const version = process.env.APP_VERSION ?? '0.0.0-dev';

new SharedStack(app, `${prefix}-Shared`, { env, stage });
new ApiStack(app, `${prefix}-Api`, { env, stage, version });
```

- [ ] **Step 25.5: Run test, expect PASS**

Note: the test mocks `execSync`? No — it actually runs Go build. Make sure Go is available locally; otherwise tests fail. For CI, the Go runtime is set up in the `cdk-diff` and `deploy-dev` jobs (already there).

```bash
cd infra && pnpm test
```

Expected: PASS.

- [ ] **Step 25.6: Local synth**

```bash
cd infra && pnpm exec cdk synth CaregiverDev-Api --context stage=dev
```

Expected: synth succeeds; CloudFormation template emitted.

- [ ] **Step 25.7: Commit**

```bash
git add infra/
git commit -m "feat(infra): api-stack with /health Lambda + HTTP API"
```

---

### Task 26: Open PR and verify dev deploy of `/health` end-to-end

**Files:** none new — leverages CI

- [ ] **Step 26.1: Push branch and open PR**

```bash
git push -u origin feat/health-lambda
gh pr create --title "feat: /health endpoint end-to-end" --body "Adds the Go Lambda handler and CDK API stack for /health." --base main
gh pr checks --watch
```

Expected: `lint`, `go-lint-test`, `cdk-diff`, `codegen-check`, `deploy-dev` all PASS.

- [ ] **Step 26.2: Hit the dev `/health` endpoint**

```bash
URL=$(aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)
curl -s "$URL/health" | jq .
```

Expected: JSON like `{"status":"ok","version":"0.0.0-dev","timestamp":"..."}`.

- [ ] **Step 26.3: Verify trace in X-Ray console**

Open the X-Ray service map in the AWS console. Expected: a trace from API Gateway → Lambda visible for the request.

- [ ] **Step 26.4: Merge and verify prod deploy**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
gh run watch
URL_PROD=$(aws cloudformation describe-stacks --stack-name CaregiverProd-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)
curl -s "$URL_PROD/health" | jq .
```

Expected: prod `/health` returns the same shape.

---

## Section 7 — Client smoke tests

### Task 27: TS smoke test for `/health` via generated client

**Files:**

- Create: `shared/types-ts/test/smoke.test.ts`, modify `shared/types-ts/package.json` to add Vitest

- [ ] **Step 27.1: Branch**

```bash
git checkout -b test/client-smoke
```

- [ ] **Step 27.2: Add Vitest**

Update `shared/types-ts/package.json` `devDependencies`:

```json
"devDependencies": {
  "openapi-typescript": "^7.4.1",
  "typescript": "^5.6.2",
  "vitest": "^2.1.1"
}
```

Update `scripts`:

```json
"scripts": {
  "codegen": "openapi-typescript ../openapi/openapi.yaml -o src/schema.gen.ts",
  "build": "pnpm codegen && tsc",
  "test": "vitest run",
  "lint": "echo 'no lint'"
}
```

- [ ] **Step 27.3: Write the smoke test**

Create `shared/types-ts/test/smoke.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { makeClient } from '../src/client';

const DEV_URL = process.env.CAREGIVER_DEV_URL;

describe('generated client /health smoke', () => {
  it.runIf(DEV_URL)('returns 200 OK with expected shape', async () => {
    const client = makeClient(DEV_URL!);
    const { data, response } = await client.GET('/health');
    expect(response.status).toBe(200);
    expect(data?.status).toBe('ok');
    expect(typeof data?.version).toBe('string');
    expect(typeof data?.timestamp).toBe('string');
  });
});
```

The test is skipped when `CAREGIVER_DEV_URL` is unset, so CI without deploy context still passes; deploy jobs set the env var.

- [ ] **Step 27.4: Install + verify locally**

```bash
pnpm install
URL=$(aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)
CAREGIVER_DEV_URL="$URL" pnpm --filter @caregiver/types-ts test
```

Expected: 1 test PASS.

- [ ] **Step 27.5: Commit**

```bash
git add shared/types-ts/
git commit -m "test(types-ts): smoke test for /health via generated client"
```

---

### Task 28: Swift smoke test for `/health` via generated client

**Files:**

- Create: `shared/types-swift/Tests/CaregiverAPITests/HealthSmokeTests.swift`
- Modify: `shared/types-swift/Package.swift` to add the test target

- [ ] **Step 28.1: Update `Package.swift` with test target**

Modify `shared/types-swift/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CaregiverAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CaregiverAPI", targets: ["CaregiverAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.2"),
    ],
    targets: [
        .target(
            name: "CaregiverAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            resources: [
                .copy("openapi.yaml"),
                .copy("openapi-generator-config.yaml"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "CaregiverAPITests",
            dependencies: ["CaregiverAPI"]
        ),
    ]
)
```

- [ ] **Step 28.2: Add the smoke test**

Create `shared/types-swift/Tests/CaregiverAPITests/HealthSmokeTests.swift`:

```swift
import XCTest
import OpenAPIURLSession
@testable import CaregiverAPI

final class HealthSmokeTests: XCTestCase {
    func testHealthRoundTripsAgainstDevURL() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["CAREGIVER_DEV_URL"],
              let url = URL(string: urlString) else {
            throw XCTSkip("CAREGIVER_DEV_URL not set; skipping live smoke.")
        }

        let client = Client(serverURL: url, transport: URLSessionTransport())
        let response = try await client.getHealth()

        switch response {
        case .ok(let ok):
            let payload = try ok.body.json
            XCTAssertEqual(payload.status, .ok)
            XCTAssertFalse(payload.version.isEmpty)
        default:
            XCTFail("Expected 200, got \(response)")
        }
    }
}
```

- [ ] **Step 28.3: Run the test locally**

```bash
cd shared/types-swift
URL=$(aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)
CAREGIVER_DEV_URL="$URL" swift test
```

Expected: 1 test PASS.

- [ ] **Step 28.4: Commit, push, PR, merge**

```bash
git add shared/types-swift/
git commit -m "test(types-swift): smoke test for /health via generated client"
git push -u origin test/client-smoke
gh pr create --title "test: client smoke tests for /health" --body "TS + Swift generated-client smoke tests against dev." --base main
gh pr checks --watch
gh pr merge --squash --delete-branch
git checkout main && git pull
```

Expected: PR passes CI, merges, prod deploy unaffected (tests don't run against prod).

---

## Section 8 — Observability

### Task 29: CloudWatch dashboard in CDK (per env)

**Files:**

- Create: `infra/lib/observability-stack.ts`, `infra/test/observability-stack.test.ts`
- Modify: `infra/bin/app.ts`, `infra/lib/api-stack.ts` (export Lambda for dashboard reference)

- [ ] **Step 29.1: Branch**

```bash
git checkout -b feat/observability
```

- [ ] **Step 29.2: Export the API Lambda from `ApiStack`**

Modify `infra/lib/api-stack.ts` — add a public field:

```ts
export class ApiStack extends cdk.Stack {
  public readonly apiFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);
    // ... existing code ...
    this.apiFunction = fn;
    // ... rest of constructor ...
  }
}
```

- [ ] **Step 29.3: Write the observability stack test**

Create `infra/test/observability-stack.test.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import { ObservabilityStack } from '../lib/observability-stack';

describe('ObservabilityStack', () => {
  test('creates one dashboard and required alarms', () => {
    const app = new cdk.App();
    const refStack = new cdk.Stack(app, 'RefStack', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    const apiFn = new lambda.Function(refStack, 'TestFn', {
      runtime: lambda.Runtime.PROVIDED_AL2023,
      handler: 'bootstrap',
      code: lambda.Code.fromInline('placeholder'),
    });
    const alarmTopic = new sns.Topic(refStack, 'AlarmTopic');

    const stack = new ObservabilityStack(app, 'TestObservability', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
      apiFunction: apiFn,
      alarmTopic,
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::CloudWatch::Dashboard', 1);
    template.resourceCountIs('AWS::CloudWatch::Alarm', 4);
  });
});
```

- [ ] **Step 29.4: Run test, expect FAIL**

```bash
cd infra && pnpm test
```

Expected: FAIL (no `ObservabilityStack`).

- [ ] **Step 29.5: Write `observability-stack.ts`**

Create `infra/lib/observability-stack.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cw from 'aws-cdk-lib/aws-cloudwatch';
import * as cwa from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import type { Stage } from './shared-stack';

export interface ObservabilityStackProps extends cdk.StackProps {
  stage: Stage;
  apiFunction: lambda.Function;
  alarmTopic: sns.Topic;
}

export class ObservabilityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ObservabilityStackProps) {
    super(scope, id, props);

    const errors = props.apiFunction.metricErrors({ period: cdk.Duration.minutes(5) });
    const throttles = props.apiFunction.metricThrottles({ period: cdk.Duration.minutes(5) });
    const duration = props.apiFunction.metricDuration({
      period: cdk.Duration.minutes(5),
      statistic: 'p95',
    });
    const invocations = props.apiFunction.metricInvocations({ period: cdk.Duration.minutes(5) });

    const action = new cwa.SnsAction(props.alarmTopic);

    const errorAlarm = new cw.Alarm(this, 'ApiErrorAlarm', {
      alarmName: `caregiver-${props.stage}-api-errors`,
      metric: errors,
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
    });
    errorAlarm.addAlarmAction(action);

    const latencyAlarm = new cw.Alarm(this, 'ApiLatencyAlarm', {
      alarmName: `caregiver-${props.stage}-api-p95-latency`,
      metric: duration,
      threshold: 2000,
      evaluationPeriods: 2,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
    });
    latencyAlarm.addAlarmAction(action);

    const throttleAlarm = new cw.Alarm(this, 'ApiThrottleAlarm', {
      alarmName: `caregiver-${props.stage}-api-throttles`,
      metric: throttles,
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
    });
    throttleAlarm.addAlarmAction(action);

    const noInvocationsAlarm = new cw.Alarm(this, 'ApiNoInvocationsAlarm', {
      alarmName: `caregiver-${props.stage}-api-no-invocations`,
      metric: invocations,
      threshold: 0,
      evaluationPeriods: 3,
      comparisonOperator: cw.ComparisonOperator.LESS_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cw.TreatMissingData.BREACHING,
    });
    // Note: noInvocationsAlarm is "informational" — for dev it's noisy; we still alarm in prod only.
    if (props.stage === 'prod') {
      noInvocationsAlarm.addAlarmAction(action);
    }

    new cw.Dashboard(this, 'Dashboard', {
      dashboardName: `Caregiver-${props.stage === 'prod' ? 'Prod' : 'Dev'}-Overview`,
      widgets: [
        [
          new cw.GraphWidget({
            title: 'API errors / 5m',
            left: [errors],
          }),
          new cw.GraphWidget({
            title: 'API p95 duration (ms) / 5m',
            left: [duration],
          }),
        ],
        [
          new cw.GraphWidget({
            title: 'API invocations / 5m',
            left: [invocations],
          }),
          new cw.GraphWidget({
            title: 'API throttles / 5m',
            left: [throttles],
          }),
        ],
      ],
    });
  }
}
```

- [ ] **Step 29.6: Wire it in `bin/app.ts`**

Modify `infra/bin/app.ts`:

```ts
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SharedStack } from '../lib/shared-stack';
import { ApiStack } from '../lib/api-stack';
import { ObservabilityStack } from '../lib/observability-stack';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION ?? 'us-east-2';
const env = { account, region };

const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';
if (stage !== 'dev' && stage !== 'prod') {
  throw new Error(`Invalid stage: ${stage}. Must be 'dev' or 'prod'.`);
}

const prefix = stage === 'prod' ? 'CaregiverProd' : 'CaregiverDev';
const version = process.env.APP_VERSION ?? '0.0.0-dev';

const shared = new SharedStack(app, `${prefix}-Shared`, { env, stage });
const api = new ApiStack(app, `${prefix}-Api`, { env, stage, version });
new ObservabilityStack(app, `${prefix}-Observability`, {
  env,
  stage,
  apiFunction: api.apiFunction,
  alarmTopic: shared.alarmTopic,
});
```

- [ ] **Step 29.7: Run tests, expect PASS**

```bash
cd infra && pnpm test
```

Expected: PASS.

- [ ] **Step 29.8: Commit**

```bash
git add infra/
git commit -m "feat(infra): observability-stack with dashboard + 4 alarms"
```

---

### Task 30: Billing alarm + AWS Budgets

**Files:**

- Create: `infra/lib/billing-stack.ts`, `infra/test/billing-stack.test.ts`
- Modify: `infra/bin/app.ts`

- [ ] **Step 30.1: Test for billing-stack (single instance, prod only)**

Create `infra/test/billing-stack.test.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as sns from 'aws-cdk-lib/aws-sns';
import { BillingStack } from '../lib/billing-stack';

describe('BillingStack', () => {
  test('creates a CloudWatch billing alarm and an AWS Budget', () => {
    const app = new cdk.App();
    const refStack = new cdk.Stack(app, 'RefStack', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    const topic = new sns.Topic(refStack, 'Topic');

    const stack = new BillingStack(app, 'TestBilling', {
      env: { account: '123456789012', region: 'us-east-1' },
      alarmTopic: topic,
      notificationEmail: 'test@example.com',
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::CloudWatch::Alarm', 1);
    template.resourceCountIs('AWS::Budgets::Budget', 1);
  });
});
```

- [ ] **Step 30.2: Run, expect FAIL**

```bash
cd infra && pnpm test
```

- [ ] **Step 30.3: Implement `billing-stack.ts`**

Create `infra/lib/billing-stack.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cw from 'aws-cdk-lib/aws-cloudwatch';
import * as cwa from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as budgets from 'aws-cdk-lib/aws-budgets';

export interface BillingStackProps extends cdk.StackProps {
  alarmTopic: sns.Topic;
  notificationEmail: string;
}

export class BillingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: BillingStackProps) {
    super(scope, id, props);

    // CloudWatch billing alarm requires us-east-1 (where AWS publishes billing metrics).
    const cwBillingMetric = new cw.Metric({
      namespace: 'AWS/Billing',
      metricName: 'EstimatedCharges',
      dimensionsMap: { Currency: 'USD' },
      period: cdk.Duration.hours(6),
      statistic: 'Maximum',
    });

    const billingAlarm = new cw.Alarm(this, 'CloudWatchSpendAlarm', {
      alarmName: 'caregiver-cloudwatch-billing-tripwire',
      metric: cwBillingMetric,
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Alerts when total CloudWatch-eligible monthly charges exceed $5.',
    });
    billingAlarm.addAlarmAction(new cwa.SnsAction(props.alarmTopic));

    new budgets.CfnBudget(this, 'OverallMonthlyBudget', {
      budget: {
        budgetName: 'caregiver-monthly-overall',
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        budgetLimit: { amount: 20, unit: 'USD' },
      },
      notificationsWithSubscribers: [
        {
          notification: {
            comparisonOperator: 'GREATER_THAN',
            notificationType: 'ACTUAL',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [{ subscriptionType: 'EMAIL', address: props.notificationEmail }],
        },
      ],
    });
  }
}
```

- [ ] **Step 30.4: Wire it (prod-only)**

Modify `infra/bin/app.ts` — add at the end:

```ts
if (stage === 'prod') {
  const notificationEmail = process.env.CAREGIVER_ALERT_EMAIL ?? 'change-me@example.com';
  new (require('../lib/billing-stack').BillingStack)(app, `${prefix}-Billing`, {
    env,
    alarmTopic: shared.alarmTopic,
    notificationEmail,
  });
}
```

Cleaner version using a static import (replace the `require` with an import at the top of the file):

```ts
import { BillingStack } from '../lib/billing-stack';
// ... and at the bottom:
if (stage === 'prod') {
  const notificationEmail = process.env.CAREGIVER_ALERT_EMAIL ?? 'change-me@example.com';
  // BillingStack MUST be in us-east-1: AWS only publishes billing metrics there.
  new BillingStack(app, `${prefix}-Billing`, {
    env: { account: env.account, region: 'us-east-1' },
    alarmTopic: shared.alarmTopic,
    notificationEmail,
  });
}
```

- [ ] **Step 30.5: Set the alert email as a GitHub variable**

```bash
gh variable set CAREGIVER_ALERT_EMAIL --body "<YOUR_EMAIL>"
```

Modify the prod workflow (`.github/workflows/cd-main.yml`) to pass `CAREGIVER_ALERT_EMAIL`:

In the `CDK deploy prod` step:

```yaml
- name: CDK deploy prod
  env:
    CAREGIVER_ALERT_EMAIL: ${{ vars.CAREGIVER_ALERT_EMAIL }}
  run: pnpm --filter @caregiver/infra exec cdk deploy --all --context stage=prod --require-approval never
```

- [ ] **Step 30.6: Test passes**

```bash
cd infra && pnpm test
```

Expected: PASS.

- [ ] **Step 30.7: Commit**

```bash
git add infra/ .github/workflows/cd-main.yml
git commit -m "feat(infra): billing alarm + AWS Budgets at \$20/mo"
```

---

### Task 31: Open PR, deploy observability + billing, verify alarms

**Files:** none new

- [ ] **Step 31.1: Push and PR**

```bash
git push -u origin feat/observability
gh pr create --title "feat: observability + billing tripwires" --body "Dashboard, alarms, billing alarm, AWS Budget." --base main
gh pr checks --watch
```

- [ ] **Step 31.2: Merge, watch prod deploy**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
gh run watch
```

- [ ] **Step 31.3: Verify dashboard in CloudWatch console**

Open CloudWatch → Dashboards → `Caregiver-Prod-Overview`. Expected: 4 widgets rendering.

- [ ] **Step 31.4: Force an alarm to test the email**

Temporarily set the error threshold to 0 and merge, or invoke the Lambda with a broken handler. Cleaner: manually trigger the alarm in the console:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name caregiver-prod-api-errors \
  --state-value ALARM \
  --state-reason "Manual test of alarm pipeline"
```

Expected: email arrives within ~1 minute. Reset:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name caregiver-prod-api-errors \
  --state-value OK \
  --state-reason "Reset after manual test"
```

---

## Section 9 — Feature flags

### Task 32: AppConfig application + profile in shared-stack

**Files:**

- Modify: `infra/lib/shared-stack.ts`, `infra/test/shared-stack.test.ts`
- Create: `infra/lib/appconfig-content.ts` (default flag JSON), `infra/lib/appconfig-schema.json`

- [ ] **Step 32.1: Branch**

```bash
git checkout -b feat/feature-flags
```

- [ ] **Step 32.2: Add the schema file**

Create `infra/lib/appconfig-schema.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "flags_demo": {
      "type": "object",
      "required": ["enabled"],
      "properties": {
        "enabled": { "type": "boolean" }
      },
      "additionalProperties": false
    }
  },
  "required": ["flags_demo"],
  "additionalProperties": false
}
```

- [ ] **Step 32.3: Add default content**

Create `infra/lib/appconfig-content.ts`:

```ts
export const defaultFlagContent = {
  flags_demo: { enabled: false },
};
```

- [ ] **Step 32.4: Extend `shared-stack` test**

Modify `infra/test/shared-stack.test.ts` — add new test:

```ts
import * as appconfig from 'aws-cdk-lib/aws-appconfig';

test('creates AppConfig application + profile + deployment', () => {
  const app = new cdk.App();
  const stack = new SharedStack(app, 'TestSharedAC', {
    env: { account: '123456789012', region: 'us-east-1' },
    stage: 'dev',
  });
  const template = Template.fromStack(stack);
  template.resourceCountIs('AWS::AppConfig::Application', 1);
  template.resourceCountIs('AWS::AppConfig::ConfigurationProfile', 1);
  template.resourceCountIs('AWS::AppConfig::Environment', 1);
  template.resourceCountIs('AWS::AppConfig::HostedConfigurationVersion', 1);
  template.resourceCountIs('AWS::AppConfig::DeploymentStrategy', 1);
  template.resourceCountIs('AWS::AppConfig::Deployment', 1);
});
```

- [ ] **Step 32.5: Run test, expect FAIL**

```bash
cd infra && pnpm test
```

- [ ] **Step 32.6: Add AppConfig resources to `shared-stack.ts`**

Modify `infra/lib/shared-stack.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as appconfig from 'aws-cdk-lib/aws-appconfig';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { defaultFlagContent } from './appconfig-content';

export type Stage = 'dev' | 'prod';

export interface SharedStackProps extends cdk.StackProps {
  stage: Stage;
}

export class SharedStack extends cdk.Stack {
  public readonly alarmTopic: sns.Topic;
  public readonly appConfigApplicationId: string;
  public readonly appConfigEnvironmentId: string;
  public readonly appConfigProfileId: string;

  constructor(scope: Construct, id: string, props: SharedStackProps) {
    super(scope, id, props);

    const stageLabel = props.stage === 'prod' ? 'Prod' : 'Dev';

    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `caregiver-${props.stage}-alarms`,
      displayName: `Caregiver ${stageLabel} Alarms`,
    });

    const appConfigApp = new appconfig.CfnApplication(this, 'FlagsApp', {
      name: `caregiver-${props.stage}`,
    });

    const schema = fs.readFileSync(path.join(__dirname, 'appconfig-schema.json'), 'utf-8');
    const validatorContent = JSON.stringify({ schemaVersion: '2.0.0', schema: JSON.parse(schema) });

    const profile = new appconfig.CfnConfigurationProfile(this, 'FlagsProfile', {
      applicationId: appConfigApp.ref,
      name: 'flags',
      locationUri: 'hosted',
      type: 'AWS.Freeform',
      validators: [
        {
          type: 'JSON_SCHEMA',
          content: JSON.stringify(JSON.parse(schema)),
        },
      ],
    });

    const env = new appconfig.CfnEnvironment(this, 'FlagsEnv', {
      applicationId: appConfigApp.ref,
      name: props.stage,
    });

    const hostedVersion = new appconfig.CfnHostedConfigurationVersion(this, 'FlagsVersion', {
      applicationId: appConfigApp.ref,
      configurationProfileId: profile.ref,
      contentType: 'application/json',
      content: JSON.stringify(defaultFlagContent),
    });

    const strategy = new appconfig.CfnDeploymentStrategy(this, 'FlagsStrategy', {
      name: `caregiver-${props.stage}-all-at-once`,
      deploymentDurationInMinutes: 0,
      growthFactor: 100,
      finalBakeTimeInMinutes: 0,
      replicateTo: 'NONE',
    });

    new appconfig.CfnDeployment(this, 'FlagsDeploy', {
      applicationId: appConfigApp.ref,
      configurationProfileId: profile.ref,
      configurationVersion: hostedVersion.ref,
      environmentId: env.ref,
      deploymentStrategyId: strategy.ref,
    });

    this.appConfigApplicationId = appConfigApp.ref;
    this.appConfigEnvironmentId = env.ref;
    this.appConfigProfileId = profile.ref;

    new cdk.CfnOutput(this, 'AppConfigApplicationId', { value: this.appConfigApplicationId });
    new cdk.CfnOutput(this, 'AppConfigEnvironmentId', { value: this.appConfigEnvironmentId });
    new cdk.CfnOutput(this, 'AppConfigProfileId', { value: this.appConfigProfileId });

    cdk.Tags.of(this).add('Project', 'Caregiver');
    cdk.Tags.of(this).add('Stage', props.stage);
  }
}
```

- [ ] **Step 32.7: Run tests, expect PASS**

```bash
cd infra && pnpm test
```

- [ ] **Step 32.8: Commit**

```bash
git add infra/lib/ infra/test/
git commit -m "feat(infra): appconfig application + flags_demo seed"
```

---

### Task 33: Add AppConfig Lambda extension layer + permissions to API

**Files:**

- Modify: `infra/lib/api-stack.ts`

- [ ] **Step 33.1: Take `appConfig*` IDs as props**

Modify `infra/lib/api-stack.ts` props:

```ts
export interface ApiStackProps extends cdk.StackProps {
  stage: Stage;
  version: string;
  appConfigApplicationId: string;
  appConfigEnvironmentId: string;
  appConfigProfileId: string;
}
```

- [ ] **Step 33.2: Add the AppConfig extension layer**

Inside the `ApiStack` constructor, after `const fn = new lambda.Function(...)`, add:

```ts
// ARM64 AppConfig extension layer ARN — region-specific.
// us-east-2 published account: 728743619870.
// Layer version below was current at plan-write time; VERIFY against the AWS docs
// before deploying: https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-integration-lambda-extensions-versions.html
const appConfigExtensionLayerArn =
  'arn:aws:lambda:us-east-2:728743619870:layer:AWS-AppConfig-Extension-Arm64:67';

fn.addLayers(
  lambda.LayerVersion.fromLayerVersionArn(this, 'AppConfigExtension', appConfigExtensionLayerArn),
);

fn.addEnvironment('APPCONFIG_APPLICATION_ID', props.appConfigApplicationId);
fn.addEnvironment('APPCONFIG_ENVIRONMENT_ID', props.appConfigEnvironmentId);
fn.addEnvironment('APPCONFIG_PROFILE_ID', props.appConfigProfileId);

fn.addToRolePolicy(
  new (require('aws-cdk-lib/aws-iam').PolicyStatement)({
    actions: ['appconfig:GetLatestConfiguration', 'appconfig:StartConfigurationSession'],
    resources: ['*'],
  }),
);
```

(Cleaner: `import * as iam from 'aws-cdk-lib/aws-iam';` at the top and use `new iam.PolicyStatement(...)`.)

- [ ] **Step 33.3: Update `bin/app.ts` to pass the IDs**

```ts
const api = new ApiStack(app, `${prefix}-Api`, {
  env,
  stage,
  version,
  appConfigApplicationId: shared.appConfigApplicationId,
  appConfigEnvironmentId: shared.appConfigEnvironmentId,
  appConfigProfileId: shared.appConfigProfileId,
});
```

- [ ] **Step 33.4: Update `api-stack.test.ts` to pass the new props**

Modify `infra/test/api-stack.test.ts`:

```ts
const stack = new ApiStack(app, 'TestApi', {
  env: { account: '123456789012', region: 'us-east-1' },
  stage: 'dev',
  version: '0.0.0-test',
  appConfigApplicationId: 'app-test',
  appConfigEnvironmentId: 'env-test',
  appConfigProfileId: 'profile-test',
});
```

- [ ] **Step 33.5: Run tests, expect PASS**

```bash
cd infra && pnpm test
```

- [ ] **Step 33.6: Commit**

```bash
git add infra/
git commit -m "feat(infra): appconfig extension layer on api lambda"
```

---

### Task 34: Add flag-fetch helper in `shared/go-common`

**Files:**

- Create: `shared/go-common/flags/flags.go`, `shared/go-common/flags/flags_test.go`

- [ ] **Step 34.1: Write the failing test**

Create `shared/go-common/flags/flags_test.go`:

```go
package flags

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestClient_Get_ReturnsDecodedFlags(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"flags_demo": map[string]any{"enabled": true},
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	flags, err := c.Get(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	demo, ok := flags["flags_demo"].(map[string]any)
	if !ok {
		t.Fatalf("flags_demo not present: %v", flags)
	}
	if demo["enabled"] != true {
		t.Errorf("expected enabled=true, got %v", demo["enabled"])
	}
}
```

- [ ] **Step 34.2: Run test, expect FAIL**

```bash
cd shared/go-common && go test ./flags
```

- [ ] **Step 34.3: Implement `flags.go`**

Create `shared/go-common/flags/flags.go`:

```go
// Package flags fetches the current feature-flag configuration from the
// AppConfig Lambda extension, which exposes a local HTTP endpoint on
// http://localhost:2772/applications/{appId}/environments/{envId}/configurations/{profileId}.
//
// In Lambda, the extension caches values in-process (default 45s TTL), so
// every call here is effectively free after the first hit.
package flags

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	url        string
	httpClient *http.Client
}

func NewClient(url string) *Client {
	return &Client{
		url:        url,
		httpClient: &http.Client{Timeout: 2 * time.Second},
	}
}

// NewClientFromEnv builds the extension URL from APPCONFIG_* environment variables.
func NewClientFromEnv(appID, envID, profileID string) *Client {
	url := fmt.Sprintf(
		"http://localhost:2772/applications/%s/environments/%s/configurations/%s",
		appID, envID, profileID,
	)
	return NewClient(url)
}

func (c *Client) Get(ctx context.Context) (map[string]any, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("appconfig extension returned %d: %s", resp.StatusCode, body)
	}
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out, nil
}
```

- [ ] **Step 34.4: Run test, expect PASS**

```bash
cd shared/go-common && go test ./flags
```

- [ ] **Step 34.5: Commit**

```bash
git add shared/go-common/
git commit -m "feat(go-common): appconfig extension flag client"
```

---

### Task 35: Add `GET /flags` to the OpenAPI spec and Lambda

**Files:**

- Modify: `shared/openapi/openapi.yaml`, `api/cmd/lambda/mux.go`
- Create: `api/internal/handlers/flags.go`, `api/internal/handlers/flags_test.go`

- [ ] **Step 35.1: Add `/flags` to OpenAPI**

Modify `shared/openapi/openapi.yaml` — under `paths:`:

```yaml
/flags:
  get:
    operationId: getFlags
    summary: Return evaluated feature flags
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Flags'
```

Add to `components.schemas`:

```yaml
Flags:
  type: object
  additionalProperties: true
  example:
    flags_demo:
      enabled: false
```

- [ ] **Step 35.2: Regenerate clients**

```bash
pnpm --filter @caregiver/types-ts run build
(cd shared/types-go && make codegen)
cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
```

- [ ] **Step 35.3: Write the handler test**

Create `api/internal/handlers/flags_test.go`:

```go
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fakeFlagSource struct {
	flags map[string]any
	err   error
}

func (f fakeFlagSource) Get(ctx context.Context) (map[string]any, error) {
	return f.flags, f.err
}

func TestFlagsHandler_ReturnsFlagsJSON(t *testing.T) {
	h := NewFlags(fakeFlagSource{flags: map[string]any{"flags_demo": map[string]any{"enabled": true}}})
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/flags", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	var got map[string]any
	if err := json.NewDecoder(rr.Body).Decode(&got); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	demo, ok := got["flags_demo"].(map[string]any)
	if !ok || demo["enabled"] != true {
		t.Errorf("expected flags_demo.enabled=true, got %v", got)
	}
}

func TestFlagsHandler_ReturnsInternalServerErrorOnSourceFailure(t *testing.T) {
	h := NewFlags(fakeFlagSource{err: errors.New("boom")})
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/flags", nil))
	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rr.Code)
	}
}
```

- [ ] **Step 35.4: Run, expect FAIL**

```bash
cd api && go test ./...
```

- [ ] **Step 35.5: Implement the handler**

Create `api/internal/handlers/flags.go`:

```go
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
)

type FlagSource interface {
	Get(ctx context.Context) (map[string]any, error)
}

type Flags struct {
	source FlagSource
}

func NewFlags(src FlagSource) *Flags {
	return &Flags{source: src}
}

func (h *Flags) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	flags, err := h.source.Get(r.Context())
	if err != nil {
		http.Error(w, "could not load flags", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(flags)
}
```

- [ ] **Step 35.6: Wire in `mux.go`**

Modify `api/cmd/lambda/mux.go`:

```go
package main

import (
	"net/http"
	"os"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/flags"
)

func newMux(cfg config.Config) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))

	flagClient := flags.NewClientFromEnv(
		os.Getenv("APPCONFIG_APPLICATION_ID"),
		os.Getenv("APPCONFIG_ENVIRONMENT_ID"),
		os.Getenv("APPCONFIG_PROFILE_ID"),
	)
	mux.Handle("GET /flags", handlers.NewFlags(flagClient))
	return mux
}
```

- [ ] **Step 35.7: Run tests, expect PASS**

```bash
cd api && go test ./...
```

- [ ] **Step 35.8: Commit**

```bash
git add shared/openapi/ shared/types-ts/ shared/types-go/ shared/types-swift/ api/
git commit -m "feat(api): GET /flags backed by appconfig extension"
```

---

### Task 36: Open PR, deploy, verify flag round-trip

**Files:** none new

- [ ] **Step 36.1: Push and PR**

```bash
git push -u origin feat/feature-flags
gh pr create --title "feat: feature flags via AppConfig + GET /flags" --body "AppConfig wiring, Lambda extension layer, /flags endpoint." --base main
gh pr checks --watch
```

- [ ] **Step 36.2: Verify dev `/flags`**

```bash
URL=$(aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)
curl -s "$URL/flags" | jq .
```

Expected: `{"flags_demo":{"enabled":false}}`.

- [ ] **Step 36.3: Toggle the flag via AppConfig console (dev app)**

In the AWS console, open AppConfig → `caregiver-dev` → Configuration Profiles → `flags` → Create new hosted version with `{"flags_demo":{"enabled":true}}`, then deploy to the `dev` environment with the all-at-once strategy.

- [ ] **Step 36.4: Re-fetch `/flags`**

```bash
sleep 60 && curl -s "$URL/flags" | jq .
```

Expected: `{"flags_demo":{"enabled":true}}` (after the 45-second extension cache TTL elapses).

- [ ] **Step 36.5: Merge**

```bash
gh pr merge --squash --delete-branch
git checkout main && git pull
```

---

## Section 10 — Renovate + final docs

### Task 37: Add Renovate config

**Files:**

- Create: `renovate.json`

- [ ] **Step 37.1: Branch**

```bash
git checkout -b chore/renovate
```

- [ ] **Step 37.2: Write `renovate.json`**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":dependencyDashboard",
    ":semanticCommitTypeAll(chore)",
    "schedule:weekly"
  ],
  "labels": ["deps"],
  "packageRules": [
    {
      "matchUpdateTypes": ["minor", "patch"],
      "matchCurrentVersion": "!/^0/",
      "automerge": false,
      "groupName": "non-major minor/patch"
    },
    {
      "matchUpdateTypes": ["major"],
      "addLabels": ["deps-major"]
    },
    {
      "matchManagers": ["gomod"],
      "groupName": "go modules"
    }
  ],
  "vulnerabilityAlerts": {
    "labels": ["security"],
    "automerge": false
  }
}
```

- [ ] **Step 37.3: Install Renovate GitHub App on the repo**

Visit https://github.com/apps/renovate and install on the `caregiver-v2` repo.

- [ ] **Step 37.4: Commit + PR + merge**

```bash
git add renovate.json
git commit -m "chore: configure renovate"
git push -u origin chore/renovate
gh pr create --title "chore: configure renovate" --body "Renovate weekly schedule, grouped minor/patch updates." --base main
gh pr checks --watch
gh pr merge --squash --delete-branch
git checkout main && git pull
```

Expected within ~1 hour: Renovate opens a "Configure Renovate" PR if it detects anything to update.

---

### Task 38: Write `docs/runbook.md`

**Files:**

- Create: `docs/runbook.md`

- [ ] **Step 38.1: Branch**

```bash
git checkout -b docs/runbook
```

- [ ] **Step 38.2: Write `docs/runbook.md`**

Create `docs/runbook.md`:

````markdown
# Runbook

Day-to-day operations for the Caregiver v2 monorepo.

## The dev loop

1. Branch from `main`:

   ```bash
   git checkout main && git pull
   git checkout -b feat/<short-name>
   ```

2. Make changes.
3. Run local checks:

   ```bash
   pnpm exec prettier --check .
   pnpm --filter @caregiver/infra test
   (cd api && go test ./...)
   (cd shared/go-common && go test ./...)
   ```

4. Commit using Conventional Commits (`feat:`, `fix:`, etc.). Lefthook enforces the format on commit.
5. Push and open a PR:

   ```bash
   gh pr create --fill
   ```

6. CI deploys your branch to dev automatically. The `cdk-diff` comment shows infra changes.
7. Once green, merge:

   ```bash
   gh pr merge --squash --delete-branch
   ```

   Merge triggers the prod deploy.

## Adding a new HTTP endpoint

1. Add the path to `shared/openapi/openapi.yaml`.
2. Run codegen (pre-commit will do this for you):

   ```bash
   pnpm --filter @caregiver/types-ts run build
   (cd shared/types-go && make codegen)
   cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
   ```

3. Write a failing handler test in `api/internal/handlers/`.
4. Implement the handler. Wire it in `api/cmd/lambda/mux.go`.
5. Run tests:

   ```bash
   (cd api && go test ./...)
   ```

6. Commit, push, open PR.

## Adding a feature flag

1. Add the flag definition to `infra/lib/appconfig-schema.json`:

   ```json
   "feat_my_thing": {
     "type": "object",
     "required": ["enabled"],
     "properties": { "enabled": { "type": "boolean" } }
   }
   ```

2. Add it to `infra/lib/appconfig-content.ts` with `enabled: false`.
3. Write an ADR at `docs/adr/NNNN-feat-my-thing.md` describing the flag, default, and retirement criteria.
4. Add code that reads the flag via `flags.Client.Get(ctx)` and checks `flags["feat_my_thing"].(map[string]any)["enabled"]`.
5. After deploy, toggle the flag in the AWS AppConfig console.

## Adding an ADR

1. Copy `docs/adr/_template.md` to `docs/adr/NNNN-kebab-title.md` with the next number.
2. Fill in context, options, decision, consequences.
3. Commit with `docs: ADR-NNNN <title>`.

## Common operations

### See what's deployed

```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE | grep Caregiver
```

### Tail Lambda logs

```bash
aws logs tail /aws/lambda/<function-name> --follow
```

### Manually trigger an alarm (test pipeline)

```bash
aws cloudwatch set-alarm-state \
  --alarm-name caregiver-prod-api-errors \
  --state-value ALARM \
  --state-reason "Pipeline test"
```

### Cost check

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -v-30d +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics UnblendedCost
```

## Troubleshooting

| Symptom                                | Likely cause                    | Action                                                         |
| -------------------------------------- | ------------------------------- | -------------------------------------------------------------- |
| CI lint fails on Prettier              | Unformatted files committed     | `pnpm exec prettier --write . && git commit --amend --no-edit` |
| Commit rejected                        | Bad commit message              | Reword with Conventional Commits prefix                        |
| `cdk diff` shows surprise changes      | CDK or context drift            | Read the diff, compare with what your code says                |
| Lambda 500 with "missing required env" | Forgot to add an env var in CDK | Add to `api-stack.ts`, redeploy                                |
| AppConfig fetch returns stale value    | Extension cache TTL             | Wait 45s, or restart the Lambda runtime                        |

## Links

- Spec: [`docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`](specs/2026-06-06-f1-engineering-practices-baseline-design.md)
- ADRs: [`docs/adr/`](adr/)
- Plans: [`docs/plans/`](plans/)
````

- [ ] **Step 38.3: Commit**

```bash
git add docs/runbook.md
git commit -m "docs: runbook for dev loop, endpoint/flag/ADR additions"
```

---

### Task 39: Update root `README.md` to point at the runbook

**Files:**

- Modify: `README.md`

- [ ] **Step 39.1: Update `README.md` "Quickstart" section**

Replace the `## Quickstart` section's body in `README.md` with:

````markdown
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
````

- [ ] **Step 39.2: Commit, push, open PR, merge**

```bash
git add README.md
git commit -m "docs: link README to runbook"
git push -u origin docs/runbook
gh pr create --title "docs: runbook + README" --body "Adds the operational runbook and links it from the README." --base main
gh pr checks --watch
gh pr merge --squash --delete-branch
git checkout main && git pull
```

---

### Task 40: Final §18 success-criteria walkthrough

This task verifies the F1 spec's success criteria are all satisfied. It produces no new code — only a verification report.

- [ ] **Step 40.1: Verify monorepo + branch protection**

```bash
gh repo view --json url,visibility,defaultBranchRef
gh api repos/:owner/:repo/branches/main/protection | jq '.required_pull_request_reviews, .required_status_checks, .allow_force_pushes'
```

Expected: repo exists, force pushes disabled, status checks required, PR reviews required.

- [ ] **Step 40.2: Verify CI runs on every PR**

Open the latest PR and confirm `lint`, `go-lint-test`, `cdk-diff`, `codegen-check`, `deploy-dev` all ran.

- [ ] **Step 40.3: Verify deploy on PR and merge**

```bash
aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].LastUpdatedTime'
aws cloudformation describe-stacks --stack-name CaregiverProd-Api --query 'Stacks[0].LastUpdatedTime'
```

Expected: timestamps within recent PR/merge events.

- [ ] **Step 40.4: Verify OpenAPI codegen round-trip**

```bash
curl -s "$(aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)/health" | jq .
URL=$(aws cloudformation describe-stacks --stack-name CaregiverDev-Api --query 'Stacks[0].Outputs[?OutputKey==`HttpApiUrl`].OutputValue' --output text)
CAREGIVER_DEV_URL="$URL" pnpm --filter @caregiver/types-ts test
(cd shared/types-swift && CAREGIVER_DEV_URL="$URL" swift test)
```

Expected: live response, TS smoke test PASS, Swift smoke test PASS.

- [ ] **Step 40.5: Verify flag toggle**

(Already done in Task 36.)

- [ ] **Step 40.6: Verify CloudWatch dashboards + alarms wired to email**

Open CloudWatch console → Dashboards → `Caregiver-Prod-Overview`. Trigger the test alarm:

```bash
aws cloudwatch set-alarm-state --alarm-name caregiver-prod-api-errors --state-value ALARM --state-reason "F1 final check"
```

Expected: email received within ~1 minute. Reset.

- [ ] **Step 40.7: Verify billing alarms armed**

```bash
aws cloudwatch describe-alarms --alarm-names caregiver-cloudwatch-billing-tripwire | jq '.MetricAlarms[0].StateValue'
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) --query 'Budgets[?BudgetName==`caregiver-monthly-overall`]'
```

Expected: alarm exists; budget exists.

- [ ] **Step 40.8: Verify seed ADRs 0001-0010 written**

```bash
ls docs/adr/*.md | wc -l
```

Expected: at least 10 (plus `_template.md`).

- [ ] **Step 40.9: Verify runbook exists**

```bash
test -f docs/runbook.md && echo "ok"
```

Expected: `ok`.

- [ ] **Step 40.10: Tag the F1 milestone**

```bash
git tag -a f1-complete -m "F1 — Engineering Practices Baseline complete"
git push origin f1-complete
```

This serves as the closing marker for F1. Future work (B1, B2, ...) builds on the rails laid down here.

---

## Notes

- **Repo lives in the `care-giver-app` GitHub org.** All Go module paths use `github.com/care-giver-app/caregiver-v2/...` and the IAM trust policy is scoped to `repo:care-giver-app/caregiver-v2:*`. If the org name changes later, update those references together.
- **Replace `<ACCOUNT>` with your 12-digit AWS account ID** in Task 10 and `cdk bootstrap` (Task 13).
- **Replace `<YOUR_EMAIL>`** in Task 13/17/30 wherever it appears.
- **Region `us-east-2` is the default for all stacks except `BillingStack`.** The CloudWatch billing alarm in `BillingStack` is pinned to `us-east-1` (Task 30, Step 30.4) because AWS only publishes billing metrics there. AWS Budgets is global, so the budget portion works regardless of stack region.
- **Free-tier reminder.** The `noInvocationsAlarm` only alerts in prod (Task 29) — in dev, an idle environment would page constantly.

## Notes added during execution

### v1/v2 coexistence (added 2026-06-06)

After Task 16, we audited the shared AWS account 658340567265 and confirmed v1 lives entirely in us-east-2 with these stack/resource patterns:

- CFN stacks: `care-giver-*-{dev,prod}` (different naming pattern from v2 — no collision risk)
- DynamoDB tables: **unprefixed** — `event-table-{dev,prod}`, `user-table-{dev,prod}`, `receiver-table-{dev,prod}`, `relationship-table-{dev,prod}`, `tracker-table-dev`
- Lambda functions: `care-giver-*-{dev,prod}` (no collision)
- SNS topics: none with caregiver naming

We added ADR-0011 and a CDK synth-time guardrail (in `infra/bin/app.ts`) that throws if any stack name doesn't match `^Caregiver(Dev|Prod)-`. Run on every `cdk synth`, in every CI job, and on every prod deploy.

**Constraint for B1 (multi-tenant data model spec, when written):** v2 DynamoDB tables MUST be prefixed (e.g., `caregiver-v2-<entity>` or `caregiver-{stage}-<entity>`) to avoid colliding with v1's unprefixed tables. Document this in the B1 spec when it's written.

**Constraint for post-F1 IAM tightening:** `CaregiverGitHubDeploy` currently has `AdministratorAccess`. A future ADR should tighten it to resources tagged `Project: Caregiver-v2`. Deferred.
