# B3a — Core Care Domain (Receivers, Trackers, Events)

- **Status:** Draft
- **Date:** 2026-06-12
- **Deciders:** Trevor Williams
- **Roadmap phase:** B3 — API surface (see `docs/roadmap.md`), first slice
- **Builds on:** B1 (`docs/specs/2026-06-11-b1-data-model-identity-design.md`)

## 1. Purpose

Ship the **core care domain** the iOS MVP (C1) consumes: a member can add a **Receiver** to a care
group, define **Trackers** for that receiver (custom or cloned from a built-in template), **log
Events** against a tracker, and page back through time-ordered history. Every record stays
structurally isolated to its care group, reusing the B1 authorization seam unchanged.

This is the **critical-path slice** of B3. It is the minimum contract that unblocks C1's core flows
(_authenticate → dashboard → log an event → view history_) and generates the Swift client those
flows are built against.

## 2. Context

B3 ("API surface") as scoped in the roadmap bundles seven subsystems: Receivers, member management,
Trackers, Events, Schedules, NotificationPreferences, and an Audit read API. Three of those
(Schedules, NotificationPreferences, Audit) feed the **async layer (B2)** and the _full_ iOS app
(C2), not the MVP. The critical path is `B3 → C1`, and C1 only needs _Receivers + Trackers + Events_.

B3 is therefore **decomposed** into independently-specced slices:

- **B3a (this spec)** — Receivers + Trackers + Events. Unblocks C1.
- **B3b (later)** — Schedules + NotificationPreferences + Audit read API. Sequenced with B2/C2.
- **Member management** (remove member, change role, leave, last-admin guard) remains its own later
  slice; the B1 data model already supports it.

B1 deferred the `care_group 1—* receiver` link to B3 ("the receiver→group link will live on the
receiver row… in B3"). B3a delivers it.

### 2.1 Decisions locked during brainstorming

| Decision                  | Choice                                                                                                     |
| ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Slice scope               | **Receivers + Trackers + Events** only; Schedules/NotifPrefs/Audit and member management deferred          |
| Tracker richness          | **Full vision** — custom typed field schema, alert thresholds, all kinds in the enum                       |
| Tracker kinds             | `event` \| `measurement` \| `scheduled` — **`event_with_note` dropped** (redundant; see §6.3)              |
| `scheduled` kind          | **Reserved in the enum**; the Schedule entity, recurrence, and reminders stay in B3b/B2 (inert until then) |
| Templates                 | **System-seeded, global, read-only catalog**, embedded in the API binary; cloned via normal tracker create |
| Permissions               | **Admins manage structure** (Receivers, Trackers); **all members log/edit/delete Events and read**         |
| `care_group_id` placement | **Denormalized** onto tracker and event rows for single-read authz (see §5.1)                              |
| Delete semantics          | **Soft-archive** for receivers & trackers (preserve history); **hard-delete** for individual events        |
| Event value model         | **Schema-on-tracker, values-as-map on event, server-validated**; `breached` flag computed on read, no push |

## 3. Goals

- The receiver→group link and per-receiver trackers, so C1 has something to display and log against.
- A **custom field schema** on trackers expressive enough that C2's tracker builder is a UI over the
  same contract — no contract churn when C2 ships.
- A built-in **template catalog** (the v1 event-type configs) so C1 has quick-start trackers with
  zero authoring UI.
- **Server-side validation** of event values against the tracker schema — the API is the single
  contract boundary for iOS and (later) web.
- Threshold evaluation surfaced as a derived `breached` flag for display, with **no notification
  side effect** (that reaction is B2).
- Tenant isolation that reuses B1's `RequireMember`/`RequireAdmin` **unchanged**, proven by an
  isolation test suite extended to the new endpoints.
- Pay down the B1-flagged store duplication / missing-pagination tech debt where we are already
  adding three more stores.

## 4. Non-Goals (deferred)

- **Schedule entity, recurrence rules, next-occurrence, reminders** → B3b / B2. The `scheduled` kind
  is accepted but inert.
- **Notifications / push on a threshold breach** → B2. B3a only computes the `breached` flag.
- **User-/group-authored templates and a template-authoring API** → C2. The B3a catalog is
  read-only and embedded.
- **Hard cascade-delete of receivers/trackers; un-archive / restore flows** → later. B3a soft-archives.
- **Member management** (remove member, change role, leave a group, last-admin guard) → its own slice.
- **Analytics rollups, audit log** → B2.

## 5. Domain model & tables

Three new entities, **multi-table, one table per entity**, prefixed `caregiver-{stage}-<entity>` per
ADR-0011 — consistent with B1. Relationships:

```
care_group ──< receiver ──< tracker ──< event
```

### 5.0 Tables

**`receiver`** — a care recipient in a group

|                       |                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| **PK**                | `receiver_id` (uuid)                                                                               |
| Attrs                 | `care_group_id`, `name`, `date_of_birth` (optional), `created_by`, `created_at`, `archived` (bool) |
| **GSI** `group-index` | PK `care_group_id`, SK `created_at` — list a group's receivers                                     |

**`tracker`** — a per-receiver thing-to-log

|                          |                                                                                                                                                   |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PK**                   | `tracker_id` (uuid)                                                                                                                               |
| Attrs                    | `receiver_id`, **`care_group_id`** (denormalized), `name`, `kind`, `icon`, `color`, `fields` (schema, §6), `created_by`, `created_at`, `archived` |
| **GSI** `receiver-index` | PK `receiver_id`, SK `created_at` — list a receiver's trackers                                                                                    |

**`event`** — a logged entry against a tracker

|                      |                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **PK**               | `tracker_id`, **SK** `event_id` (uuid) — direct GetItem for get/edit/delete                                                    |
| Attrs                | **`care_group_id`, `receiver_id`** (denormalized), `values` (map), `note` (optional), `occurred_at`, `logged_by`, `created_at` |
| **GSI** `time-index` | PK `tracker_id`, SK `occurred_at` — time-ordered history, paginated, `from`/`to` range                                         |

### 5.1 Denormalizing `care_group_id`

`care_group_id` is copied onto the `tracker` and `event` rows at create time. Authorization then
resolves the owning group with a **single GetItem** — the tracker (for event-create/list) or the
event (for event-edit/delete) — instead of walking `event → tracker → receiver → group` on the
logging hot path. This reuses the exact B1 seam: resolve the id, then `RequireMember`/`RequireAdmin`.

**Constraint that makes this safe:** a receiver cannot move between care groups. The copied value
describes something that never changes, so it can never drift. Moving a receiver is not a feature and
is explicitly out of scope; were it ever added, it would require rewriting the denormalized values on
all descendant rows.

### 5.2 Delete semantics

`DELETE` on a receiver or tracker sets `archived = true` — it is hidden from list endpoints, but its
descendant data is preserved. This is a care log; removing a receiver must not silently destroy
history. Individual events may be **hard-deleted** (`DELETE …/events/{id}`) to correct a mistake.
Hard cascade-delete and un-archive flows are deferred.

### 5.3 Store helpers (tech-debt fold-in)

The B1 review (`docs/TECH_DEBT.md`) flagged that the stores copy-paste their
`GetItem`/`UnmarshalMap` and `Query`/`UnmarshalListOfMaps` blocks and that list queries lack
pagination. B3a adds three more stores and the event-history endpoint **requires** real pagination,
so this slice extracts generic `getItem[T]` / `queryItems[T]` and a cursor (LastEvaluatedKey)
helper in `shared/go-common/store/store.go`, and the new stores consume them. Retrofitting the four
B1 stores onto the helpers is optional and may stay a separate follow-up.

## 6. Tracker schema & template catalog

### 6.1 Field schema

A tracker's `fields` is an ordered list of typed field definitions — this is what makes trackers
custom. Each field:

```jsonc
{
  "key": "systolic", // stable identifier; the key used in event.values
  "label": "Systolic", // display name
  "type": "number", // number | text | boolean | enum | datetime
  "unit": "mmHg", // optional; number only
  "required": true, // must be present on every event
  "options": ["low", "ok"], // required iff type == enum
  "threshold": { "min": 90, "max": 140 }, // optional; number only
}
```

- **Five field types:** `number`, `text`, `boolean`, `enum` (single-select from `options`),
  `datetime` (RFC 3339).
- **`threshold`** (number fields only) stores `min`/`max` bounds. B3a stores and **evaluates** them
  into a derived `breached` flag on event read — it sends no notification (that is B2).

### 6.2 Kinds

`kind ∈ event | measurement | scheduled` is an explicit semantic/presentation hint, not a separate
schema:

- `event` — typically zero fields ("took a walk"); the built-in optional `note` captures any comment.
- `measurement` — one or more `number` fields with units/thresholds (weight, BP, temperature).
- `scheduled` — **reserved**. Behaves like its underlying fields; with no Schedule entity it produces
  no reminders until B3b. Creating one is allowed; it is inert.

`kind` is kept (rather than inferred from the schema shape) so clients get an unambiguous semantic
signal — a measurement may also carry a text field, so shape-sniffing would be brittle.

### 6.3 Why `event_with_note` was dropped

The roadmap listed a fourth kind, `event_with_note`. It carries **no data difference**: every event
row already has a built-in optional `note`, so a note attaches to any event regardless of kind. The
only behaviors a separate kind could add — "show the note prominently" or "require a note" — are
better expressed by the field schema ("require a note" is literally `{ type: "text", required: true }`)
or by the always-available `note`. Dropping it removes a redundant concept with no lost capability.
This is a deliberate deviation from the roadmap's four-kind list.

### 6.4 Template catalog

A `TrackerTemplate` has the same creatable shape as a tracker minus per-receiver identity:
`{ template_id, name, kind, icon, color, fields }`. The catalog is an **embedded `templates.json`**
(`//go:embed`) seeded with the v1 event-type configs (e.g. weight, blood pressure, temperature,
medication, meals, mood). A CI unit test parses it into the Go struct so a malformed or
schema-drifted catalog **fails the build**.

- `GET /tracker-templates` returns the catalog (read-only; authenticated, no group scoping).
- **Cloning is normal tracker creation.** The client reads a template, optionally edits the fields,
  and `POST`s it to `/receivers/{id}/trackers`. There is **no clone endpoint and no server-side
  link** — a template is a starting payload, the resulting tracker is a full independent copy, and
  editing a template later never disturbs existing trackers.

**Forward path:** when templates become runtime-authored (C2), move the catalog behind the same
`GET /tracker-templates` contract into S3 or DynamoDB — the API surface does not change, so it is a
clean swap. Embedding is chosen for B3a because the runtime-edit benefit is unreachable until a
template-authoring surface exists, and embedding keeps the catalog under the same
contract-validation guarantees as the rest of the code.

## 7. Event model & validation

### 7.1 Shape

What a client POSTs to log an event:

```jsonc
{
  "occurred_at": "2026-06-12T14:30:00Z", // when it happened; defaults to now() if omitted
  "values": { "systolic": 128, "diastolic": 82 }, // keyed by field.key
  "note": "after lunch", // optional freeform; always available
}
```

The server fills `event_id`, `logged_by` (from the auth context), `created_at`, and the denormalized
`care_group_id` / `receiver_id`. The response echoes the stored row plus derived breach info (§7.3).

**An event belongs to exactly one tracker.** Capturing several readings at once (e.g. systolic +
diastolic + pulse) is done with a **multi-field tracker** — the `values` map holds all of them — not
by associating one event with multiple trackers. Logging several _independent_ trackers in one user
gesture (a "morning check-in") is a client/UI concern (a batch of one-tracker events), not a
many-to-many data model; a `POST /events:batch` convenience can be added later if needed without
changing the event keying.

### 7.2 Validation (server-side, against the tracker's field schema)

1. **Unknown keys rejected** — every key in `values` must match a `field.key`. → 400
2. **Required fields present** — every `required` field must appear. → 400
3. **Type-checked per field:** `number` → JSON number; `text` → string; `boolean` → bool;
   `enum` → must be one of `field.options` (else 400); `datetime` → RFC 3339 string.
4. **`occurred_at`** must parse as RFC 3339; defaults to server `now()` if omitted.

A failure returns a single 400 naming the offending field, via B1's `httpx.WriteError` style. An
out-of-range number is **valid data** — never rejected, only flagged (§7.3). `PATCH` re-runs the
same validation.

### 7.3 Threshold evaluation → `breached`

On event **read** (single or list), the server compares each `number` value against its field's
`threshold` and attaches a derived, **non-stored** flag:

```jsonc
"breaches": [{ "key": "systolic", "value": 162, "bound": "max", "limit": 140 }]
```

Computed fresh on read (not persisted) so that editing a threshold re-evaluates historical events
correctly. **No notification, no side effect** — purely a display signal for C1. The reaction to a
breach is B2.

## 8. Authorization & tenant isolation

Reuses B1's middleware and predicates **unchanged**. Each handler resolves `care_group_id` from the
path (or via a single denormalized GetItem) and then calls:

- `RequireMember(groupID)` — read and event mutation routes.
- `RequireAdmin(groupID)` — receiver and tracker structural routes (create/edit/archive).

**Permissions summary:**

| Action                                         | Who        |
| ---------------------------------------------- | ---------- |
| Create / edit / archive **Receivers**          | Admin      |
| Create / edit / archive **Trackers**           | Admin      |
| Read receivers / trackers / events / templates | Any member |
| Log / edit / delete **Events**                 | Any member |

Any member can edit or delete any event in their group — there is no author-or-admin restriction;
cross-group mutation remains impossible because every event mutation runs `RequireMember` on the
event's denormalized `care_group_id`. A cross-tenant id resolves to 404/403, never data.

## 9. Endpoints

OpenAPI-first (ADR-0003); Go server types and the Swift client are regenerated from the contract.
All routes are authenticated and wrapped with `authn.Wrap`. Creates are nested under their parent so
the group is in the path; reads/edits/deletes of a specific item use the flat top-level form and
resolve the group via one GetItem — mirroring B1's mix.

| Method & path                                               | Authz         | Effect                                               |
| ----------------------------------------------------------- | ------------- | ---------------------------------------------------- |
| `GET /receivers[?careGroupId=]`                             | RequireMember | list receivers in the caller's groups (or one group) |
| `POST /care-groups/{careGroupId}/receivers`                 | RequireAdmin  | create a receiver                                    |
| `GET /receivers/{receiverId}`                               | RequireMember | get one                                              |
| `PATCH /receivers/{receiverId}`                             | RequireAdmin  | rename / set date of birth                           |
| `DELETE /receivers/{receiverId}`                            | RequireAdmin  | archive (soft)                                       |
| `GET /receivers/{receiverId}/trackers`                      | RequireMember | list a receiver's trackers                           |
| `POST /receivers/{receiverId}/trackers`                     | RequireAdmin  | create a tracker (incl. from a template payload)     |
| `GET /trackers/{trackerId}`                                 | RequireMember | get one                                              |
| `PATCH /trackers/{trackerId}`                               | RequireAdmin  | edit name / icon / color / fields                    |
| `DELETE /trackers/{trackerId}`                              | RequireAdmin  | archive (soft)                                       |
| `GET /trackers/{trackerId}/events?limit=&cursor=&from=&to=` | RequireMember | paginated, time-ordered history (newest first)       |
| `POST /trackers/{trackerId}/events`                         | RequireMember | log an event                                         |
| `GET /trackers/{trackerId}/events/{eventId}`                | RequireMember | get one                                              |
| `PATCH /trackers/{trackerId}/events/{eventId}`              | RequireMember | edit a logged event                                  |
| `DELETE /trackers/{trackerId}/events/{eventId}`             | RequireMember | hard-delete an event                                 |
| `GET /tracker-templates`                                    | authenticated | read-only seeded catalog                             |

Notes:

- **Event addressing.** Event get/edit/delete are nested under the tracker
  (`/trackers/{trackerId}/events/{eventId}`) so both the partition key (`tracker_id`) and sort key
  (`event_id`) are in the path — no addressing GSI needed.
- **Pagination.** `GET …/events` returns `{ "items": [...], "next_cursor": "…" }`; `next_cursor` is an
  opaque base64 of the DynamoDB `LastEvaluatedKey`. `from`/`to` filter on `occurred_at` via
  `time-index`. Newest-first (`ScanIndexForward=false`).

## 10. Code placement

| Concern                                                                              | Location                                                     |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| Domain models (`Receiver`, `Tracker`, `Field`, `Event`), kind/type enums, validation | `shared/go-common/domain/`                                   |
| Stores + generic `getItem[T]` / `queryItems[T]` / cursor helpers                     | `shared/go-common/store/`                                    |
| Embedded template catalog (`templates.json` + loader + CI validation test)           | `shared/go-common/domain/` (or `templates`)                  |
| HTTP handlers (`receivers.go`, `trackers.go`, `events.go`, `templates.go`)           | `api/internal/handlers/`                                     |
| Route wiring                                                                         | `api/cmd/lambda/mux.go`                                      |
| OpenAPI paths + schemas (source of truth) → regenerated Go + Swift                   | `shared/openapi/`, `shared/types-go/`, `shared/types-swift/` |
| 3 DynamoDB tables + GSIs, env wiring                                                 | `infra/lib/shared-stack.ts`, `api-stack.ts`                  |

The OpenAPI contract is authored first (ADR-0003); Go and Swift types are generated so the C1 iOS
client consumes a real contract.

## 11. Testing strategy

Testing-trophy (ADR-0006) — static + integration carry the weight, as in B1.

- **Integration (bulk)** — handlers + stores against DynamoDB Local (testcontainers): receiver /
  tracker / event CRUD; pagination cursor round-trips; `from`/`to` filtering; soft-archive hides from
  lists while preserving events; template list and clone-via-create.
- **Validation suite** — unknown key, missing required, wrong type, enum miss, `occurred_at` parse;
  threshold → `breached` computation, including re-evaluation after a threshold edit.
- **Isolation suite (security gate, own file)** — extends B1's: a member of group 1 cannot read,
  create, edit, or delete any receiver, tracker, or event in group 2 through _any_ new endpoint; a
  caregiver gets 403 on the admin-only structural routes; cross-tenant ids return 404/403, never data.
- **Unit** — field-schema validation, threshold evaluation, cursor encode/decode, embedded-catalog
  parse (fails the build on drift).
- **Static / drift** — codegen-drift check regenerates TS + Go + Swift from the contract and copies
  the spec into the Swift package.

## 12. Open questions / forward constraints

- **`scheduled` activation (B3b).** A scheduled tracker is inert in B3a. B3b adds the Schedule entity
  and recurrence; the tracker `kind` enum already reserves the value, so no contract change is needed.
- **Template store migration (C2).** When templates become runtime-authored, swap the embedded
  catalog for S3/DynamoDB behind the unchanged `GET /tracker-templates` contract.
- **Receiver immutability of group.** Denormalization assumes a receiver never changes care group; if
  that becomes a feature, descendant `care_group_id` values need a rewrite path.
- **Store-helper retrofit.** Retrofitting the four B1 stores onto the new generic helpers is optional
  and may remain a `TECH_DEBT.md` follow-up.

## 13. Success criteria

B3a is complete when:

- The 3 tables + GSIs deploy via CDK to dev and prod, with env wiring into the API Lambda.
- An admin can create a receiver, create a tracker (from a template or from scratch), a caregiver can
  log a measurement event, and any member can page back through time-ordered history with a
  `breached` flag surfacing on out-of-range values.
- Server-side validation rejects malformed event values (unknown key, missing required, wrong type,
  enum miss) with a field-named 400.
- The isolation suite passes: no member reaches another group's receivers/trackers/events through any
  endpoint, and admin-only structural routes reject caregivers.
- The OpenAPI contract for these endpoints generates Go server types and a Swift client.
- All checks green in CI.
