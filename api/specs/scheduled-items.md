# Scheduled Items (Schedules — B3b, v1)

- **Module:** api
- **Status:** Draft (B3b, first cut)
- **Last updated:** 2026-07-15
- **Contract:** `POST/GET /trackers/{trackerId}/scheduled-items`, `GET /receivers/{receiverId}/scheduled-items`, `GET/PUT/DELETE /scheduled-items/{scheduledItemId}` → `ScheduledItem` (new ops + schemas in `shared/openapi/openapi.yaml`)
- **Related specs:** B3a core care domain (`docs/specs/2026-06-12-b3a-core-care-domain-design.md`); consumed by [[home]] and [[trackers]] (ios); B2 will consume these rows for reminders.

> Living, conceptual spec for one module (api). The interface to clients is owned by the OpenAPI
> contract; this spec references it but never duplicates it.

## Purpose

Activates the reserved `scheduled` tracker kind (B3a `domain/care.go:13`). A tracker of kind
`scheduled` owns a list of **scheduled items** — discrete, dated, planned entries (a doctor visit, a
medication time, a therapy session, a bill-due date). Each item is a single `scheduled_for` datetime
with an optional note. This is the backend contract the iOS **Home "Coming up" banner** and the
tracker **"Due"/upcoming** states bind to — both are deliberately unbuilt today because "the contract
has no schedule/cadence" ([[home]] decisions 3–4, 8; [[trackers]] decision 6).

A `ScheduledItem` is deliberately distinct from an `Event`: an `Event` is something that **happened**
(`occurred_at`, past, logged); a `ScheduledItem` is something **planned** (`scheduled_for`, future).

## Behavior

A scheduled item is **created under a tracker** (which supplies `receiver_id` / `care_group_id`) but
is **listable by receiver** (for the cross-tracker banner) and addressable **by its own id**.

- **Authorization:** **any member** may create/read/update/delete scheduled items (`RequireMember`) —
  scheduling care is day-to-day coordination, mirroring how all members log Events. Admins still
  solely manage the tracker itself (create/rename/archive). Non-members get `403`.
- **Create** (`POST /trackers/{trackerId}/scheduled-items`): the tracker must exist, not be archived,
  and be `kind == scheduled` (else `400`). Server assigns `scheduled_item_id`, denormalizes
  `tracker_id` / `receiver_id` / `care_group_id` from the tracker, stamps `created_by` (`ac.UserID`)
  and `created_at`. Returns `201` + the full `ScheduledItem`.
- **List by tracker** (`GET /trackers/{trackerId}/scheduled-items`): a tracker's items, **soonest
  first**, with optional `from`/`to` (RFC3339) window and `limit`/`cursor` pagination.
- **List by receiver** (`GET /receivers/{receiverId}/scheduled-items`): **the Home "Coming up"
  banner** — every scheduled item across the receiver's scheduled trackers, soonest first, same
  `from`/`to`/`limit`/`cursor` params (banner passes `from=now`).
- **Get / Update / Delete** (`/scheduled-items/{scheduledItemId}`): `GET` reads one; `PUT` reschedules
  or edits the note (replace semantics, carrying denormalized fields through unchanged, per B3a's
  full-item PutItem pattern); `DELETE` hard-deletes (like Events). All resolve authz off the item's
  denormalized `care_group_id` in a single read.
- **Errors:** `401` unauthenticated, `403` non-member, `404` missing tracker/item, `400` validation
  (`kind != scheduled`, missing/unparseable `scheduled_for`), `500` store failure — via `httpx`.

**No stored `next_occurrence`.** "Next" is just the earliest future row, which the soonest-first
queries surface directly — no materialized field to keep fresh.

## Data model

New entity `ScheduledItem`, new table `caregiver-{stage}-scheduled-item` (multi-table per ADR-0011).

| field               | notes                                                       |
| ------------------- | ----------------------------------------------------------- |
| `scheduled_item_id` | PK, uuid                                                    |
| `tracker_id`        | owning scheduled tracker (denormalized)                     |
| `receiver_id`       | denormalized from tracker → powers the receiver-wide banner |
| `care_group_id`     | denormalized → single-read authz (B3a pattern)              |
| `scheduled_for`     | RFC3339 datetime, **required**                              |
| `note`              | optional text                                               |
| `created_by`        | `ac.UserID`                                                 |
| `created_at`        | server timestamp                                            |

Two GSIs, both mirroring the existing `receiver-index` shape on `store/tracker.go`:

- `tracker-index` — PK `tracker_id`, SK `scheduled_for` (list a tracker's items by date)
- `receiver-index` — PK `receiver_id`, SK `scheduled_for` (list a receiver's items by date — banner)

## Key decisions

| Decision           | Choice                                                                   | Why                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Schedule ↔ tracker | A schedule is a **cadence on a tracker**; activates the `scheduled` kind | The kind was reserved for exactly this (B3a §12); reuses tracker authz/scoping; no `TrackerKind` enum change           |
| Cadence model (v1) | **Discrete scheduled items only** — 1 tracker → many dated items         | Matches the "add appointments to a Dr tracker" mental model; no recurrence engine needed for the first cut             |
| Recurrence         | **Deferred** (future work)                                               | Real appointments are irregular; a rule engine is unnecessary now and can be added per-item later without churn        |
| Entity name        | **`ScheduledItem`** (not `Appointment`/`Schedule`)                       | Generic across appointments, meds, therapy, bills — a scheduled tracker isn't always appointments                      |
| `next_occurrence`  | **Not stored** — earliest future row via soonest-first query             | Avoids stale materialized state; keeps B3b self-contained. B2 can materialize later if a reminder job needs it         |
| Authz              | **`RequireMember`** for all CRUD; admins still own tracker structure     | Scheduling care is day-to-day coordination (like logging Events), not structural config                                |
| Receiver-wide list | Denormalize `receiver_id` + `receiver-index` GSI                         | Makes the cross-tracker Home banner a single query instead of an N+1 fan-out over the receiver's trackers              |
| Delete semantics   | **Hard delete** (like Events)                                            | Scheduled items are transient future data; past ones simply age out of `from=now` queries                              |
| Archive cascade    | **None in v1** (known gap)                                               | Archiving a scheduled tracker leaves its items; the banner could show an archived tracker's item — revisit if it bites |

> **Routes are registered in two places.** A new path must be added to BOTH the Go mux
> (`api/cmd/lambda/mux.go`) AND the CDK `authedRoutes` list (`infra/lib/api-stack.ts`). A route present
> only in the Go mux returns **404** at the API Gateway — the exact trap [[members]] hit.

## Where it lives

| Concept                                                                      | File                                                                 |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Domain: `ScheduledItem` struct                                               | `shared/go-common/domain/scheduled_item.go` (new)                    |
| Store: Put/Get/Delete/list-by-\*                                             | `shared/go-common/store/scheduled_item.go` (new)                     |
| Store registration + GSI consts                                              | `shared/go-common/store/store.go`                                    |
| Test table + GSIs                                                            | `shared/go-common/store/dynamotest/dynamotest.go`                    |
| Handler: authz + validate + JSON                                             | `api/internal/handlers/scheduled_items.go` (new)                     |
| Route wiring (Go mux) + `*_TABLE`                                            | `api/cmd/lambda/mux.go`                                              |
| Table + GSIs (CDK)                                                           | `infra/lib/shared-stack.ts`                                          |
| Env var + API Gateway routes (CDK)                                           | `infra/lib/api-stack.ts` (`addEnvironment`, `authedRoutes`)          |
| Contract: ops + `ScheduledItem` + `ScheduledItemWrite` + `ScheduledItemList` | `shared/openapi/openapi.yaml`                                        |
| Store tests                                                                  | `shared/go-common/store/scheduled_item_test.go` (new)                |
| Handler tests + isolation                                                    | `api/internal/handlers/scheduled_items_test.go`, `isolation_test.go` |
| Route registration test                                                      | `infra/test/api-stack.test.ts`                                       |

## Non-goals

- **No recurrence rules** — discrete items only in v1; recurrence is deferred future work.
- **No reminders / notifications / APNs** — B2 consumes these rows to fire reminders; B3b only stores
  and serves them.
- **No `next_occurrence` field** — derived on read, never materialized.
- **No NotificationPreferences or Audit-read** — the other two B3b sub-features are deferred until
  they have consumers (B2's orchestrator and B2's mutation-write path, respectively).
- **No archive cascade** — see the known gap in Key decisions.
