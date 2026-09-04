# B1 — Data Model & Identity (Multi-Tenant Foundation)

- **Status:** Draft
- **Date:** 2026-06-11
- **Deciders:** Trevor Williams
- **Roadmap phase:** B1 (see `docs/roadmap.md`)
- **Builds on:** F1 (`docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`)

## 1. Purpose

Establish the multi-tenant data model and identity substrate that every later Caregiver v2 phase
builds on. B1 makes one thing true and proven end-to-end: **a person can sign in, create or join a
care group, and the system structurally isolates one group's data from another's.** It also ships
the thin slice of endpoints that exercises that path, so multi-tenant isolation is demonstrated
through a real authenticated request rather than asserted on paper.

## 2. Context

F1 built the engineering rails (monorepo, CI/CD, CDK, AppConfig flags, observability) but no product
feature. The roadmap sequences B1 first because B3 (API surface) needs a data model, the clients
(C-phases) need something to authenticate against, and the table-prefix constraint from ADR-0011 has
been waiting on B1.

v1 had no tenant concept — a caregiver saw a receiver only if a `Relationship` row connected them
(`User ↔ Relationship ↔ Receiver`), with isolation enforced implicitly by per-handler relationship
checks. v2 makes the tenant boundary explicit and structural.

**Decisions locked during brainstorming:**

| Decision              | Choice                                                                               |
| --------------------- | ------------------------------------------------------------------------------------ |
| Tenancy boundary      | Explicit **`CareGroup`** tenant; `care_group_id` scopes every record                 |
| Group shape           | A group is a household with one-or-more receivers; a user can belong to many groups  |
| Member roles          | **Admin** + **Caregiver**                                                            |
| Storage               | Multi-table, one table per entity, prefixed `caregiver-{stage}-<entity>`             |
| Identity provisioning | **JIT in authz middleware** — create the `user` row on first authenticated request   |
| B1 endpoint scope     | Foundation + identity/membership flows; domain CRUD is B3                            |
| Invite acceptance     | **Token-first**: token is the credential; in-app discovery by email is a convenience |

## 3. Goals

- A **structural** tenant boundary: cross-group access is impossible by construction, not by
  remembering to check.
- Identity that links cleanly to AWS Cognito with **no client orchestration** (no v1-style
  `custom:db_user_id` round-trip).
- A reusable authorization primitive (`RequireMember` / `RequireAdmin`) that every future handler
  consumes unchanged.
- An invite/accept flow that works **entirely in-app with zero outbound email** (no dependency on
  SES production access).
- Validated by integration tests against DynamoDB Local, with a dedicated isolation test suite.

## 4. Non-Goals (deferred)

- **Receiver, Event, Tracker, Schedule, and all domain CRUD** → B3 (and B2 for async). B1 creates
  none of those tables.
- **Member management** — remove a member, change a role, leave a group, and the "a group must keep
  at least one admin" guard → B3.
- **Outbound email / push** (invite notification nudges) → B2.
- **v1 → v2 data migration**, including whether to reuse the v1 Cognito user pool → B4.
- **Federated sign-in design** (Sign in with Apple/Google) beyond noting its impact on email
  matching → its own design when clients are built.

## 5. Domain model

Relationships: `care_group 1—* receiver` (receiver in B3), `user *—* care_group` via
`membership(role)`, and `invitation` is a staged future membership keyed by email + token.

```
user ──< membership >── care_group ──< receiver (B3)
                            ^
                            └──< invitation (pending → membership on accept)
```

B1 creates **four tables**. The broader v2 domain model (receiver, event, tracker, …) is the target
documented in the roadmap, but those tables and endpoints land in their own phases when their access
patterns are designed — standing them up empty now would be speculative.

### 5.1 `user` — app-side identity (created by JIT)

|                       |                                                |
| --------------------- | ---------------------------------------------- |
| **PK**                | `user_id` (= Cognito `sub`)                    |
| Attrs                 | `email`, `name`, `created_at`                  |
| **GSI** `email-index` | PK `email` — match invites to a signed-up user |

`user_id` **is** the Cognito `sub`. No separate identifier, no linking attribute round-trip.

### 5.2 `care_group` — the tenant

|        |                                    |
| ------ | ---------------------------------- |
| **PK** | `care_group_id`                    |
| Attrs  | `name`, `created_by`, `created_at` |

The receiver→group link will live on the **receiver** row (FK on the child) in B3, so this item is
its final shape — adding receivers later requires no change to `care_group` and no backfill.

### 5.3 `membership` — grants access (replaces v1 `Relationship`)

|                       |                                                                                      |
| --------------------- | ------------------------------------------------------------------------------------ |
| **PK**                | `user_id`, **SK** `care_group_id` — "what groups is this user in?" (the authz query) |
| Attrs                 | `role` (`admin` \| `caregiver`), `created_at`                                        |
| **GSI** `group-index` | PK `care_group_id`, SK `user_id` — "who's in this group?"                            |

### 5.4 `invitation` — pending invite by email + token

|                       |                                                                                                                             |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **PK**                | `token` (128-bit crypto-random, single-use) — accept-by-token lookup                                                        |
| Attrs                 | `care_group_id`, `email`, `role`, `status` (`pending`/`accepted`/`revoked`), `invited_by`, `created_at`, `expires_at` (TTL) |
| **GSI** `group-index` | PK `care_group_id` — list a group's pending invites                                                                         |
| **GSI** `email-index` | PK `email` — show a new signup their pending invites                                                                        |

`expires_at` uses DynamoDB TTL (14 days) to auto-expire stale invites.

## 6. Identity & provisioning

**Cognito** owns authentication (credentials, future federated sign-in, the `sub`). The `user` table
owns app identity, keyed by `sub`. These are deliberately separate responsibilities that v1 blurred.

**Provisioning is JIT (just-in-time) in the authz middleware.** The token is validated by the API
Gateway HTTP API **JWT authorizer** before any handler runs, so the handler receives verified claims
(`sub`, `email`, `name`) in the request context. On the first authenticated request for an unknown
`sub`, the middleware creates the `user` row from those verified claims via a conditional write
(`attribute_not_exists`), making it idempotent under concurrent first-requests.

Rationale: the membership lookup needed for authorization already happens on every scoped request, so
JIT rides on a load-bearing path and adds only a one-time write per user lifetime — no extra hot-path
read, no second Lambda (Cognito trigger), no client orchestration. **Provisioning grants no access:**
a new `user` has zero memberships and can reach nothing until they create a group or accept an invite.

## 7. Authorization & tenant isolation

The security core. Goal: cross-tenant access is impossible by construction.

**Per-request auth context**, assembled once by middleware:

1. Read verified claims from the authorizer context → `sub`, `email`, `name`.
2. JIT-ensure the `user` row.
3. Query `membership` by `user_id` → `Memberships: map[care_group_id]role`.
4. Attach `AuthContext { UserID, Email, Memberships }` to the request.

**The isolation rule (applied everywhere):** a group-scoped endpoint takes its `care_group_id` from
the path/resource, then authorizes via:

- `RequireMember(groupID)` → 403 unless `Memberships[groupID]` exists.
- `RequireAdmin(groupID)` → 403 unless that role is `admin`.

Because access derives entirely from `Memberships`, default-deny falls out of the model. No handler
reads a group's data by raw ID without first clearing the membership check. This is the exact seam
B3 reuses: a receiver-scoped request resolves `receiver → care_group_id` and calls the same
`RequireMember` — unchanged.

## 8. Endpoints (the B1 slice)

| Endpoint                                                    | Auth               | Effect                                     | Writes                                             |
| ----------------------------------------------------------- | ------------------ | ------------------------------------------ | -------------------------------------------------- |
| `GET /me`                                                   | any authed         | bootstrap; triggers JIT                    | `user` (if missing)                                |
| `POST /care-groups`                                         | any authed         | create group, become Admin                 | `care_group` + `membership(admin)` (transactional) |
| `POST /care-groups/{id}/invitations`                        | `RequireAdmin(id)` | invite by email                            | `invitation(pending)`                              |
| `GET /invitations/mine`                                     | any authed         | discover pending invites by verified email | —                                                  |
| `POST /invitations/{token}/accept`                          | the invitee        | join the group                             | `membership` + invitation→accepted (transactional) |
| `DELETE /care-groups/{id}/invitations/{token}` _(optional)_ | `RequireAdmin(id)` | revoke a pending invite                    | invitation→revoked                                 |

- **`GET /me`** → `{ user, memberships: [{care_group_id, name, role}] }`. The membership query yields
  IDs + roles; batch-get `care_group` rows for names. This is the iOS launch call that decides the
  first-run path (empty memberships → "create or join a group").
- **`POST /care-groups`** `{ name }` → 201 `{ care_group_id, name, role: "admin" }`. Group + admin
  membership in one `TransactWriteItems` — a group can never exist without its creator's admin row.
- **`POST …/invitations`** `{ email, role }` → 201 `{ token, email, role, expires_at }`. Email
  normalized lowercase; reject if already a member (`group-index`) or already has a pending invite;
  `token` returned for sharing through any channel.

## 9. Invitations & acceptance

**Token-first, two paths, zero outbound email.** Nothing in B1 sends mail — the token is returned in
the API response, so SES (including sandbox limits) is never a dependency. Email _sending_ is an
optional B2 nudge only.

- **In-app discovery (convenience):** an invitee signs in and calls `GET /invitations/mine`, which
  queries the `invitation` `email-index` by their verified email and surfaces pending invites for an
  in-app **Accept** — no email ever sent. Covers the common case where the invitee's email matches.
- **Shareable token (robust):** the admin shares the returned invite code/link directly (text, in
  person); the invitee accepts on the **token** regardless of email. This covers **Sign in with
  Apple "Hide My Email"** (private-relay addresses won't match the invited email) and any case where
  the app email differs from the invited one.

**Accept rules:** the token is the credential — `POST /invitations/{token}/accept` succeeds for any
authenticated caller when the token is `pending` and unexpired; it is **not** gated on email match.
Writes `membership` (at the invited role) + flips the invitation to `accepted` in one transaction;
**idempotent** if the membership already exists. Token safety is bounded by single-use, 14-day
expiry, and admin revoke — a leaked token grants at most one group at one role.

## 10. Code placement

| Concern                                                                                 | Location                                  |
| --------------------------------------------------------------------------------------- | ----------------------------------------- |
| Domain models, DynamoDB repos, `AuthContext`, `RequireMember`/`RequireAdmin`, token gen | `shared/go-common/`                       |
| HTTP handlers + auth middleware for the 5 endpoints                                     | `api/internal/`, `api/cmd/lambda/`        |
| OpenAPI paths + schemas for the B1 endpoints (source of truth)                          | `shared/openapi/`                         |
| Generated Go server types + Swift client                                                | `shared/types-go/`, `shared/types-swift/` |
| 4 DynamoDB tables + Cognito user pool; HTTP API **JWT authorizer** + routes             | `infra/` (CDK)                            |

The OpenAPI contract is authored first (per ADR-0003); Go and Swift types are generated from it so
the iOS client in C1 consumes a real contract.

## 11. Testing strategy

Testing-trophy (ADR-0006): static + integration carry the weight.

- **Integration (bulk)** — handlers + repos against **DynamoDB Local** (testcontainers); auth
  exercised by injecting authorizer claims (we test our logic, not Cognito's signing). Cases: JIT
  create / no-op / concurrent-race idempotency; create-group transaction atomicity; invite
  (duplicate, already-member, non-admin 403); accept (valid, expired, revoked, reused, idempotent);
  discovery by email.
- **Isolation suite (security gate, own file)** — user A (group 1 only) cannot read, invite to, or
  admin group 2 through _any_ endpoint; a zero-membership user reaches nothing; `RequireAdmin`
  rejects a `caregiver`.
- **Unit** — token generation, email normalization, expiry math.
- **Static** — Go types generated from OpenAPI, `golangci-lint`, `tsc` for CDK.
- **Infra / smoke** — Cognito pool + JWT authorizer validated by `cdk synth`/diff in CI and a
  one-time deployed-dev smoke (real sign-in → `GET /me` → create group → invite → accept), since that
  path can't be fully exercised against DynamoDB Local alone.

## 12. Open questions / forward constraints

- **Apple private-relay email capture.** When federated sign-in is designed, decide whether to
  capture a user-chosen contact email in-app so email-based discovery works for relay users (the
  shareable-token path covers them in the meantime).
- **Member management + last-admin guard** are B3; the data model already supports them (role on
  `membership`).
- **B4 / v1 migration:** keying `user` on `sub` and not assuming an empty table keeps both options
  open — reuse the v1 Cognito pool (subs carry over) or map old→new by email at migration time.
- **IAM tightening** of `CaregiverGitHubDeploy` (from F1) remains a separate follow-up.

## 13. Success criteria

B1 is complete when:

- The 4 tables + Cognito user pool + JWT authorizer deploy via CDK to dev and prod.
- A real user can sign in, `GET /me` (auto-provisions), create a care group (becomes Admin), invite a
  second user, and that user can accept **in-app** — with no email sent.
- The isolation test suite passes: no caregiver can reach a group they don't belong to through any
  endpoint, and admin-only actions reject caregivers.
- The OpenAPI contract for these endpoints generates Go server types and a Swift client.
- All checks green in CI; one manual deployed-dev smoke of the full sign-in → accept path passes.
