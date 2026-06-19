# C1-UI: Activity Tab — Daily Timeline

**Date:** 2026-06-19
**Scope:** The Activity tab's first real feature — a single-day, cross-tracker event timeline for the active receiver.
**Spec series:** C1-UI design pass
**Status:** active

---

## Goal

Replace the Activity tab placeholder with a **daily timeline**: for the active receiver, show all
events logged on a chosen day, across every tracker, newest-first, with day-by-day navigation. Tapping
an event opens its existing detail screen (view / edit / delete).

The primary use case is a caregiver reviewing "what happened for this person on this day" — a single
scannable log that crosses tracker boundaries (BP, meds, weight, walks, …), which the per-tracker Home
history can't show.

---

## Decisions (settled during brainstorming)

- **Single day + date navigation**, not an infinite reverse-chronological feed. One day at a time with
  prev/next arrows, swipe, and a tap-to-jump date picker.
- **Tap an event → `EventDetailView`** (reuses the existing edit/delete screen).
- **Data source: client-side aggregation (Approach B)** — no backend or contract change. The Activity
  view fetches the active receiver's trackers, then each tracker's events for the selected day, and
  merges them. Chosen over a backend `receiver_id`-scoped endpoint (Approach A) because the single-day
  scope makes B's usual weaknesses (N+1, merged-stream pagination) negligible at family scale, and
  every endpoint it needs already exists.
  - **Future note:** if a receiver-scoped events endpoint is later built (a `receiver_id + occurred_at`
    GSI + `/receivers/{id}/events`), both this timeline _and_ the deferred Home "last reading" card
    enhancement (`docs/TECH_DEBT.md`) can consume it. That is a shared, deferred optimization — not in
    scope here.

---

## Why no backend work is needed

- `listTrackers(receiverId)` already returns a receiver's trackers.
- `listEvents(trackerId, from:, to:)` already exists and accepts `from`/`to` (`date-time`) bounds
  (`shared/openapi/openapi.yaml` → `/trackers/{trackerId}/events`), returning that tracker's events in
  the window, newest-first.
- `Event` carries `occurred_at`; `EventRef{tracker, event}` (`ios/Caregiver/App/Route.swift`) already
  couples a tracker with one of its events — the exact unit the timeline renders and navigates with.

A single day per tracker is small, so the first page (`limit`) per tracker is sufficient; merged-stream
pagination is explicitly **out of scope** (see Non-goals).

---

## Components

| Unit                                       | Responsibility                                                                | Depends on                                                      |
| ------------------------------------------ | ----------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `ActivityView`                             | The screen: date-nav header + day list + states; owns `selectedDate`.         | `ReceiverContext` (active receiver), `ActivityModel`, `Session` |
| `ActivityModel` (`@MainActor @Observable`) | Loads + merges a day's events into `[EventRef]`; owns the load state machine. | `Session.api` (`listTrackers`, `listEvents`)                    |
| `ActivityRow`                              | Renders one event row: time · tracker (name + color dot) · value summary.     | `DynamicFormBuilder.display(values:fields:)`                    |
| `ActivityDay` (small helper)               | Pure date math: day bounds + the header label.                                | `Calendar`                                                      |

`ActivityView` lives in `ios/Caregiver/Activity/` (replacing the current `ActivityView.swift`
placeholder). `ActivityModel`, `ActivityRow`, and `ActivityDay` are new files in the same folder.

---

## Data flow

`ActivityModel.load(receiverID:date:using:)`:

1. `listTrackers(receiverId)` → keep `!archived`.
2. For each tracker **concurrently** (a `withTaskGroup`): `listEvents(trackerId, query: from = dayStart,
to = dayEnd)` and take its `items`.
3. Flatten into `[EventRef]` (`EventRef(tracker:event:)` per event), **sort by `event.occurredAt`
   descending** (newest-first).
4. State → `.empty` if none, else `.loaded([EventRef])`. Any thrown error → `.error(message)` via
   `AppError.from`.

State machine: `enum State { case loading, loaded([EventRef]), empty, error(String) }`.

The view drives reloads with `.task(id: DayKey(receiverID:dayStart:))` so changing the **day** _or_ the
**active receiver** re-runs the load and auto-cancels the in-flight one.

### Day bounds

In `Calendar.current`:

- `dayStart = calendar.startOfDay(for: date)`
- `dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!` (the **next** midnight)

The window is **half-open** `[dayStart, dayEnd)` so an event at exactly midnight belongs to one day
only. (The store's `to` is inclusive `BETWEEN`, but passing the next-midnight as `to` with the dataset's
sub-second timestamps makes a real collision astronomically unlikely; if precise exclusivity is ever
needed, subtract one second from `dayEnd`.)

---

## Navigation & the stale-after-edit guard

The Activity tab is its own `NavigationStack` (in `RootView.mainStack`). The timeline pushes the event
detail by value:

- Each `ActivityRow` is wrapped in `NavigationLink(value: ref)` where `ref: EventRef`.
- `ActivityView` registers `.navigationDestination(for: EventRef.self) { ref in EventDetailView(tracker:
ref.tracker, event: ref.event) { Task { await reload() } } }`.

Wiring `EventDetailView`'s `onChange` to **reload the current day** means an edit or delete made from the
timeline refreshes on return — deliberately avoiding the "stale shared state after a mutation" bug class
logged in `docs/TECH_DEBT.md` (the archived-receiver issue).

> This uses a dedicated `EventRef` navigation destination rather than the shared
> `appRouteDestinations(me:)` modifier, because that shared modifier passes a no-op `onChange` for
> `.event` and the Activity tab only ever pushes events. `EventRef` is already `Hashable`.

---

## Date-navigation header

```
‹        Today, Jun 19        ›
```

- **Prev arrow / swipe-right:** `selectedDate -= 1 day`.
- **Next arrow / swipe-left:** `selectedDate += 1 day`, **disabled when `selectedDate` is today** (no
  future days).
- **Tap the date label:** present a graphical `DatePicker` (`.datePickerStyle(.graphical)`) bounded
  `...today` to jump to any past day.
- **Label text:** "Today" if today, "Yesterday" if the day before, else weekday + medium date
  (e.g. "Wed, Jun 17").

---

## Row layout

```
 3:10 PM   ● Blood Pressure                     ›
           120/80 mmHg
```

- **Leading:** event time only (`occurredAt`, `.short` time) — the day is already the header context.
- **Tracker:** the tracker name preceded by a small color dot (`tracker.color` → `Color(hex:)`, falling
  back to `Theme.Colors.accent`), so cross-tracker rows are distinguishable.
- **Value:** `DynamicFormBuilder.display(values: event.values, fields: tracker.fields)` — the same
  one-line summary used by the per-tracker history `EventRow`.
- Trailing chevron from the `NavigationLink`.

---

## States

| State              | UI                                                                                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| No active receiver | `EmptyStateView(message: "No receiver selected.")` (rare — a member with zero receivers); no date header is shown since there is nothing to scope to. |
| `loading`          | `LoadingView()` below the date header.                                                                                                                |
| `loaded`           | A `List` of `ActivityRow`s; `.refreshable { await reload() }` for pull-to-refresh.                                                                    |
| `empty`            | `EmptyStateView(message: "No activity on \(label).")`                                                                                                 |
| `error`            | `ErrorStateView(message:)` with a retry that calls `reload()`.                                                                                        |

The date-navigation header is **always** visible (even while loading / empty / error) so the user can
move to another day.

---

## Testing

Per repo convention, SwiftUI views are not unit-tested; the screen is gated by a green
`xcodebuild test`. The two **pure** units get real TDD coverage in `ios/CaregiverTests/`:

1. **`ActivityDay` date math** — `dayBounds(for:calendar:)` returns `[startOfDay, nextMidnight)` for a
   given date; and the header `label(for:relativeTo:calendar:)` returns "Today" / "Yesterday" /
   weekday+date correctly (test with a fixed `Calendar`/reference date, not `Date()`).
2. **Merge + sort** — a pure `ActivityModel.merge(_ perTracker: [(Tracker, [Event])]) -> [EventRef]`
   that flattens and sorts newest-first. Test: interleaved timestamps across multiple trackers come out
   strictly descending; empty input → empty; single tracker preserved.

Extracting `merge` as a static pure function (separate from the networking) is what makes it testable
and keeps `load` thin.

---

## Non-goals (YAGNI)

- **No infinite/continuous feed** — single day only.
- **No merged-stream pagination** — first page per tracker per day is sufficient; if a single tracker
  logs more than one page in one day, older same-day events for that tracker are omitted (acceptable;
  revisit only if it happens).
- **No per-tracker filter, search, or multi-receiver view.**
- **No future dates.**
- **No backend changes** (no new endpoint, no GSI) — explicitly deferred to a future shared slice.

---

## Files

| File                                          | Change                                                                                                                                                             |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ios/Caregiver/Activity/ActivityView.swift`   | **Rewrite** — date-nav header, day list, states, `EventRef` destination.                                                                                           |
| `ios/Caregiver/Activity/ActivityModel.swift`  | **Create** — load + `merge`, state machine.                                                                                                                        |
| `ios/Caregiver/Activity/ActivityRow.swift`    | **Create** — one event row.                                                                                                                                        |
| `ios/Caregiver/Activity/ActivityDay.swift`    | **Create** — day bounds + label helpers.                                                                                                                           |
| `ios/Caregiver/App/RootView.swift`            | **No change** — the Activity `NavigationStack { ActivityView() }` already exists; the `EventRef` destination is attached inside `ActivityView`, not in `RootView`. |
| `ios/CaregiverTests/ActivityDayTests.swift`   | **Create** — date-math tests.                                                                                                                                      |
| `ios/CaregiverTests/ActivityMergeTests.swift` | **Create** — merge/sort tests.                                                                                                                                     |
