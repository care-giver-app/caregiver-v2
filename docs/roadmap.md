# Caregiver v2 — Product Roadmap

> **What this is:** the high-level sequence of work for Caregiver v2 after the F1 foundations.
> It defines each phase (B1–B4, C1–C3), what it delivers, and the order to build them in.
> It is **not** a per-phase spec — each phase still goes through brainstorm → design spec
> (`docs/specs/`) → implementation plan (`docs/plans/`), the same flow F1 used.

## Naming convention

- **F** = foundations (engineering rails, no product feature)
- **B** = backend
- **C** = client

F1 (Engineering Practices Baseline) is complete and tagged `f1-complete`.

## Lineage

The product vision below is carried forward from the v1 planning doc
(`care-giver-specs/ROADMAP.md` — custom Trackers, Schedules, granular notifications, audit log,
analytics, push). That doc assumed an **evolve-in-place** approach (Angular/Amplify, extend the SAM
infra). **ADR-0001 superseded that** with a parallel rewrite: Go API + native SwiftUI iOS +
Next.js/React web, on new `caregiver-{stage}-*` tables. This roadmap re-bases the vision onto the
rewrite.

**v2 direction: iOS-first.** The native iOS app is the primary client and is built and made usable
on fresh data **before** any v1 data migration. Web remains in scope but is secondary and later.

## Phase map

| Code | Name                           | Scope                                                                           | Depends on          | Status                    |
| ---- | ------------------------------ | ------------------------------------------------------------------------------- | ------------------- | ------------------------- |
| F1   | Engineering Practices Baseline | Monorepo, CI/CD, CDK, feature flags, observability                              | —                   | ✅ Done                   |
| B1   | Data model & identity          | Entities, multi-tenant DynamoDB tables, Cognito, authz                          | F1                  | ✅ Done                   |
| B2   | Async services & notifications | `services/` layer: notif prefs, schedules, APNs push, audit, rollups, real-time | B1                  | Planned                   |
| B3a  | Core care domain               | Receivers + Trackers + Events: OpenAPI contract + Go handlers + CDK tables      | B1                  | ✅ Done                   |
| B3b  | Scheduling & prefs API         | Schedules + NotificationPreferences + Audit read API                            | B1                  | Planned                   |
| B4   | v1 → v2 migration              | Migrate the family's real data, cut over, retire v1                             | B1–B3 + iOS shipped | Planned (last)            |
| C1   | **iOS MVP** + design language  | Native SwiftUI core flows: auth, dashboard, log/view events                     | B1, B3              | **Primary / next client** |
| C2   | Full iOS                       | Tracker builder, schedules, notif prefs, analytics, audit, APNs push            | C1, B2, B3          | Planned                   |
| C3   | Web client                     | Next.js + React, AWS-native SSR (CloudFront + S3 + Lambda)                      | B1, B3, B2          | Later / secondary         |

## Critical path

```
F1 ✅ → B1 ✅ → B3a ✅ → C1 (iOS MVP)     ← first usable v2, on fresh data
                     → B2 + B3b + C2 (full iOS, can overlap)
                                 → C3 (web)
                                       → B4 (migrate family off v1, retire it — last)
```

B3 was decomposed into **B3a** (core care domain — Receivers/Trackers/Events, the slice C1 needs;
done) and **B3b** (Schedules, NotificationPreferences, Audit read — sequenced with B2/C2). See
`docs/specs/2026-06-12-b3a-core-care-domain-design.md`.

The migration (B4) is deliberately last: the iOS app must be shippable and usable on new data before
we touch the family's live v1 data.

## Domain model

Carried from v1, re-based onto v2. All tables prefixed `caregiver-{stage}-*` per ADR-0011 (avoids
collision with v1's unprefixed tables in the shared AWS account).

**Existing-vision entities:** `User`, `Receiver`, `Relationship`, `Event`.

**New entities:**

- **Tracker** — caregiver-defined per receiver. `kind` ∈ `event` / `event_with_note` /
  `measurement` / `scheduled`; carries a field schema, units, alert thresholds, icon, color. The v1
  global event-type configs become **templates** a caregiver can clone-and-customize. Events
  reference a per-receiver `tracker_id` rather than a global `type` string.
- **Schedule** — recurrence rule + next occurrence for scheduled trackers.
- **NotificationPreference** — per user × receiver × tracker × channel. Replaces the single
  `email_notifications` boolean on `Relationship`.
- **AuditLog** — append-only entry per mutation (HIPAA-aware), optional TTL.
- **Rollup** — pre-computed analytics aggregates.

**Open for B1 to decide:** the multi-tenant boundary. v1 is single-household; v2 is multi-tenant.
B1 designs the tenant/household model and the cross-tenant isolation guarantees.

## Phases in detail

### B1 — Data model & identity

The data substrate and auth everything else builds on. Domain models in `shared/go-common/`,
DynamoDB tables + a Cognito user pool defined in CDK (`shared-stack`), and relationship-based
authorization middleware with multi-tenant isolation. Honors the table-prefix constraint from
ADR-0011. **Depends on:** F1.

### B2 — Async services & notifications _(newly scoped)_

The `services/` async layer. Notification orchestrator/executor revamped around granular
`NotificationPreference`; schedule-driven reminders from the `Schedule` entity; **APNs push** for the
iOS app; audit-log middleware writing an `AuditLog` entry per mutation; analytics rollups via
DynamoDB Streams → Lambda; and support for real-time polling sync. **Depends on:** B1 (parallelizable
with B3).

### B3 — API surface _(decomposed into B3a + B3b)_

The synchronous REST API in `api/`: OpenAPI 3 contract + Go handlers, generating the Swift client
into `shared/types-swift/`. Split into two slices:

- **B3a (done)** — Receivers, Trackers (custom field schema + thresholds + seeded templates), and
  Events (validated, paginated history, computed breach flag). The slice C1 needs. Design:
  `docs/specs/2026-06-12-b3a-core-care-domain-design.md`.
- **B3b (planned)** — Schedules, NotificationPreferences, and the Audit read API; sequenced with B2
  (async) and C2 (full iOS). The `scheduled` tracker kind is reserved in B3a but inert until B3b adds
  the Schedule entity.

Member management (remove member, change role, leave, last-admin guard) remains its own later slice.
**Depends on:** B1.

### C1 — iOS MVP + design language _(primary, next client)_

The first usable client is the **native iOS app**. A design language plus the core SwiftUI flows:
authenticate via Cognito, view a dashboard, log an event against a tracker, and view history —
consuming the generated Swift client. Works entirely on fresh data, with no dependency on v1
migration. Push notifications are deferred to C2. **Depends on:** B1, B3.

### C2 — Full iOS

The complete iOS feature set: custom tracker builder, schedules, notification preferences,
analytics, audit viewer, and APNs push. **Depends on:** C1, B2, B3.

### C3 — Web client _(secondary)_

Brings the same feature set to the browser: Next.js + React (App Router) with AWS-native SSR hosting
(CloudFront + S3 + Lambda) per ADR-0010. Sequenced after the iOS app is solid. **Depends on:** B1,
B3, B2.

### B4 — v1 → v2 migration

Migrate the family's live v1 data (unprefixed tables) into v2: derive a `Tracker` per
`(receiver, type)` pair, back-fill `tracker_id` on events, cut over, and retire v1. **Runs last,
after the iOS app is shipped and usable.** **Depends on:** B1–B3 and a shipped iOS client.

## Deferred engineering follow-ups

Not product phases — loose ends carried from F1:

- Tighten the `CaregiverGitHubDeploy` IAM role from `AdministratorAccess` to least-privilege
  (follow-up ADR).
- Decide single- vs. dual-account topology (open question → future ADR).
- Sync the stale "web SSR at C2" references in ADR-0010 and the F1 spec §16 to **C3** (web moved
  later under the iOS-first reorder).
- Revisit each F1 convention after ~1 month of use; drop what hasn't paid off.
