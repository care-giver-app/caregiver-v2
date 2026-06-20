# C1-UI: Activity Tab — Daily Timeline

**Date:** 2026-06-19
**Scope:** The Activity tab's first real feature — a single-day, cross-tracker event timeline for the active receiver.
**Spec series:** C1-UI design pass
**Status:** active

---

## Goal

Replace the Activity tab placeholder with a **daily timeline**: for the active receiver, show all
events logged on a chosen day, across every tracker, on a vertical stepper rail ordered chronologically
(earliest at the top), with day-by-day navigation. Tapping an event opens its existing detail screen
(view / edit / delete).

The primary use case is a caregiver reviewing "what happened for this person on this day" — a single
scannable log that crosses tracker boundaries (BP, meds, weight, walks, …), which the per-tracker Home
history can't show.

---

## Decisions (settled during brainstorming)

- **Single day + date navigation**, not an infinite reverse-chronological feed. One day at a time with
  prev/next arrows, swipe, and a tap-to-jump date picker.
- **Tap an event → `EventDetailView`** (reuses the existing edit/delete screen).
- **Visual: a vertical timeline rail / stepper (added 2026-06-20).** Events render as equal-spaced steps
  on a left-hand rail, **earliest at the top** (chronological, not newest-first). A left gutter shows a
  day/night icon + time; the rail node is colored by the tracker. Equal spacing — **not** a scaled
  time-axis. All colors come from `Theme` tokens and rows are transparent so the `.earthBackground()`
  shows through. See the **Row layout** section.
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

| Unit                                       | Responsibility                                                                                                                                         | Depends on                                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `ActivityView`                             | The screen: date-nav header + day list + states; owns `selectedDate`.                                                                                  | `ReceiverContext` (active receiver), `ActivityModel`, `Session`                |
| `ActivityModel` (`@MainActor @Observable`) | Loads + merges a day's events into `[EventRef]`; owns the load state machine.                                                                          | `Session.api` (`listTrackers`, `listEvents`)                                   |
| `ActivityRow`                              | Renders one timeline step: gutter (day/night icon + time), rail (line + tracker-colored node, trimmed via `isFirst`/`isLast`), content (name + value). | `DynamicFormBuilder.display(values:fields:)`, `ActivityDay.isDaytime`, `Theme` |
| `ActivityDay` (small helper)               | Pure date math: day bounds, header label, and `isDaytime` (sun/moon split).                                                                            | `Calendar`                                                                     |

`ActivityView` lives in `ios/Caregiver/Activity/` (replacing the current `ActivityView.swift`
placeholder). `ActivityModel`, `ActivityRow`, and `ActivityDay` are new files in the same folder.

---

## Data flow

`ActivityModel.load(receiverID:date:using:)`:

1. `listTrackers(receiverId)` → keep `!archived`.
2. For each tracker **concurrently** (a `withTaskGroup`): `listEvents(trackerId, query: from = dayStart,
to = dayEnd)` and take its `items`.
3. Flatten into `[EventRef]` (`EventRef(tracker:event:)` per event), **sort by `event.occurredAt`
   ascending** (oldest-first, so the earliest event sits at the top of the timeline rail). Ties are
   broken by `eventId` ascending for determinism.
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

## Row layout — timeline rail

Each row is a step on a continuous vertical rail. Earliest events are at the top.

```
        │
 ☀      ●  Blood Pressure
 8:00a  │  120/80 mmHg
        │
 ☀      ●  Weight
 2:30p  │  168 lb
        │
 🌙     ●  Evening walk
 9:15p     20 min
```

`ActivityRow(ref:isFirst:isLast:)` has three columns in an `HStack(alignment: .top)`:

- **Gutter (~52pt):** a day/night icon above the event time (`occurredAt`, `.short`).
  - Icon: `Image(systemName: ActivityDay.isDaytime(occurredAt) ? "sun.max.fill" : "moon.fill")`,
    tinted `Theme.Colors.amber` for the sun and `Theme.Colors.textSecondary` for the moon.
  - Time: `Theme.Typography.caption`, `Theme.Colors.textSecondary`.
- **Rail (~24pt):** a 2pt vertical line in `Theme.Colors.ink.opacity(0.15)` with a filled **node** (a
  `Circle`) colored by the tracker (`tracker.color` → `Color(hex:)`, fallback `Theme.Colors.accent`).
  The line is trimmed **above** the first row's node and **below** the last row's node (`isFirst` /
  `isLast`) so the rail reads as a clean stepper with defined ends.
- **Content:** tracker name (`Theme.Typography.headline`, `Theme.Colors.textPrimary`) + the one-line
  `DynamicFormBuilder.display(values: event.values, fields: tracker.fields)` summary
  (`Theme.Colors.textSecondary`).

**Blending with the background:** the `List` keeps `.scrollContentBackground(.hidden)` and each row uses
`.listRowBackground(Color.clear)` + `.listRowSeparator(.hidden)`, so the `.earthBackground()` gradient
shows through and the rail is the only divider. Every color is a `Theme` token (no hardcoded values).

The whole row remains a `NavigationLink(value: ref)` (the chevron/affordance comes from the link).

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

1. **`ActivityDay` date math** — `bounds(for:calendar:)` returns `[startOfDay, nextMidnight)`; the
   header `label(for:relativeTo:calendar:)` returns "Today" / "Yesterday" / weekday+date correctly;
   and `isDaytime(_:calendar:)` returns the day/night split at the boundaries (05:59 → false/moon,
   06:00 → true/sun, 17:59 → true/sun, 18:00 → false/moon). Test with a fixed `Calendar`/reference
   date, not `Date()`.
2. **Merge + sort** — a pure `ActivityModel.merge(_ perTracker: [(Tracker, [Event])]) -> [EventRef]`
   that flattens and sorts **oldest-first (ascending)**, ties broken by `eventId` ascending. Test:
   interleaved timestamps across multiple trackers come out strictly ascending; empty input → empty;
   the equal-timestamp tiebreak is deterministic. (The existing newest-first assertions are flipped to
   ascending as part of this redesign.)

Extracting `merge` as a static pure function (separate from the networking) is what makes it testable
and keeps `load` thin.

---

## Non-goals (YAGNI)

- **No infinite/continuous feed** — single day only.
- **No merged-stream pagination** — first page per tracker per day is sufficient; if a single tracker
  logs more than one page in one day, older same-day events for that tracker are omitted (acceptable;
  revisit only if it happens).
- **No per-tracker filter, search, or multi-receiver view.**
- **No scaled/proportional time axis** — the rail is an equal-spaced stepper ordered by time, not a
  to-scale 24h axis.
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

> The table above describes the **initial build** (all merged-or-in-PR-#24). The **timeline-rail
> redesign (2026-06-20)** modifies existing files rather than creating them:
>
> | File                                          | Redesign change                                                                                                           |
> | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
> | `ios/Caregiver/Activity/ActivityRow.swift`    | **Rewrite** to the gutter + rail + content layout; add `isFirst`/`isLast`; all `Theme` colors.                            |
> | `ios/Caregiver/Activity/ActivityView.swift`   | **Modify** — `ForEach(Array(refs.enumerated()), …)` to pass `isFirst`/`isLast`; clear row background + hidden separators. |
> | `ios/Caregiver/Activity/ActivityModel.swift`  | **Modify** — flip `merge` sort to oldest-first (ascending).                                                               |
> | `ios/Caregiver/Activity/ActivityDay.swift`    | **Modify** — add `isDaytime(_:calendar:)`.                                                                                |
> | `ios/CaregiverTests/ActivityMergeTests.swift` | **Modify** — flip expectations to ascending.                                                                              |
> | `ios/CaregiverTests/ActivityDayTests.swift`   | **Modify** — add `isDaytime` boundary tests.                                                                              |
