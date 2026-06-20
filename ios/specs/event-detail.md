# Event Detail

- **Module:** ios
- **Status:** Current
- **Last updated:** 2026-06-20
- **Contract:** `deleteEvent(trackerId, eventId)`, `listMembers(careGroupId)` (`shared/openapi/openapi.yaml` → `DELETE /trackers/{trackerId}/events/{eventId}`, `GET /care-groups/{careGroupId}/members`). Edit reuses `LogEventView` (`updateEvent`).
- **Related specs:** [[activity-timeline]] and Home history both navigate here; [[members]] (api) provides the `logged_by` → name lookup.

> Living, conceptual spec for the iOS event-detail screen. The interface to the backend is owned by
> the OpenAPI contract; this spec references it but does not duplicate it.

## Purpose

The screen a caregiver lands on when they tap a single logged event (from Home history or the
Activity timeline): a clear, glance-able record of one reading — what was measured, when, by whom —
with edit and delete. It replaces the original plain-`Form` screen that showed only a single
concatenated value line, applying the earthy design language (C1-UI) and surfacing the metadata the
contract already carries.

## Behavior

A read view over one `Event` + its `Tracker`, presented as an `earthBackground` `ScrollView` of glass
cards (no `Form`):

- **Header card** — the tracker's color dot + icon, tracker name, the event time (`occurred_at` as
  relative + absolute, e.g. "Today at 8:14 AM · 2h ago"), and **"Logged by {name}"**.
- **Values card** — one row per tracker `Field`: `label` … `value` `unit`. Driven by `tracker.fields`
  so labels and units are the real schema, not a mashed string. Fields with no value are omitted.
- **Note card** — rendered only when `event.note` is non-empty.
- **Actions** — a `PrimaryButton` "Edit" opening the existing `LogEventView` edit sheet, and a
  destructive "Delete" behind a confirmation dialog. On either success, call `onChanged()` (so the
  caller — Activity day or Home history — reloads, avoiding the stale-shared-state bug class) and
  `dismiss()`.
- **Error** — a delete failure surfaces the `AppError` message inline; the screen stays put.

### Who logged it (name resolution)

`event.logged_by` is a user id, not a name. The screen resolves it via the care-group **members**
endpoint ([[members]]). Because event-detail is reached from several places, members are **not**
re-fetched per tap: a small shared `@Observable` cache keyed by `care_group_id` loads the roster
lazily (using `event.care_group_id`) and is reused across screens. Lookup `logged_by` → name; while
loading or if the id is absent (e.g. a former member), fall back to **"A care-team member"**. The name
line never blocks the rest of the screen from rendering.

## Key decisions

| Decision               | Choice                                                                | Why                                                                                            |
| ---------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Container              | `earthBackground` + glass cards, not `Form`                           | C1-UI design language; the old `Form` had no earth styling                                     |
| Values display         | Per-field rows (label · value · unit) from `tracker.fields`           | Replaces one concatenated string; real labels/units, scannable                                 |
| Surface metadata       | Show `occurred_at` + `logged_by`, which the old screen dropped        | The contract already carries them; "when / who" is core to a care record                       |
| `logged_by` → name     | Resolve via members endpoint; fall back to "A care-team member"       | No id→name map existed; honest fallback for loading / former members. Drove [[members]] (api). |
| Members fetch strategy | Shared `@Observable` cache keyed by `care_group_id`, lazy             | Event-detail has many entry points; avoids an N+1 fetch on every event tap                     |
| Breach styling         | **Deferred to C2**                                                    | `breaches[]` + `Theme.Colors.alert` are reserved for the C2 breach-badge work                  |
| Edit / delete          | Unchanged — reuse `LogEventView` sheet + confirm dialog + `onChanged` | The mutation flow already works; this is a visual + metadata redesign                          |

## Where it lives

| Concept                                             | File                                                      |
| --------------------------------------------------- | --------------------------------------------------------- |
| Screen: cards, states, edit sheet, delete confirm   | `ios/Caregiver/Events/EventDetailView.swift`              |
| Delete action + error state                         | `EventDetailModel` (in `EventDetailView.swift`)           |
| Value-rows builder (fields × values → ordered rows) | `ios/Caregiver/Events/EventDetailView.swift` (pure fn)    |
| Shared members cache (id → name, keyed by group)    | `ios/Caregiver/Support/` (new `@Observable` store)        |
| Earth/glass tokens + `.glassCard()`                 | `ios/Caregiver/DesignSystem/{Theme,Components}.swift`     |
| Tests (pure units)                                  | `ios/CaregiverTests/` (value-rows + name-lookup fallback) |

## Non-goals

- No breach/threshold alert styling — deferred to C2.
- No member roster UI — this screen only resolves a single `logged_by` to a name; the full roster is
  a future use of [[members]].
- No history/list rendering — that's Home history and [[activity-timeline]].
- No new event fields or contract changes beyond consuming [[members]].
