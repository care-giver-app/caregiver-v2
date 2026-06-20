# Activity Timeline

- **Module:** ios
- **Status:** Current
- **Last updated:** 2026-06-20
- **Contract:** `listTrackers(receiverId)`, `listEvents(trackerId, from:, to:)` (`shared/openapi/openapi.yaml` → `/receivers/{id}/trackers`, `/trackers/{trackerId}/events`). No contract changes.
- **Related specs:** C1-UI navigation; `EventDetailView` (event view/edit/delete)

> Living, conceptual spec for the iOS Activity tab. The interface to the backend is owned by the
> OpenAPI contract; this spec references it but does not duplicate it.

## Purpose

The Activity tab gives a caregiver a single, scannable answer to "what happened for this person on
this day?" — every event across every tracker (BP, meds, weight, walks…) for the active receiver,
which the per-tracker Home history can't show.

## Behavior

A **single-day, cross-tracker timeline** for the active receiver, presented as a vertical stepper
rail inside a glass widget card.

- **One day at a time.** A date-navigation header (`‹ Today, Jun 19 ›`) drives the view: prev/next
  arrows and horizontal swipe move by a day; tapping the label opens a graphical date picker bounded
  to today. No future days; "next" is disabled on today.
- **Rail layout, earliest at top.** Events render as equal-spaced steps on a left-hand rail
  (chronological, _not_ a scaled time axis). Each row: a gutter (day/night icon + time), a
  tracker-colored node on a continuous rail, and content (tracker name + one-line value summary).
- **Tap an event → `EventDetailView`** (the existing view/edit/delete screen). Returning from an edit
  or delete **reloads the current day**, avoiding the stale-shared-state bug class.
- **States** (all keep the date header visible so the user can navigate away): `loading`, `loaded`,
  `empty` ("No activity on <day>"), `error` (retry). No active receiver → full-screen empty state, no
  card.
- **Widget container.** The tab is a vertical stack of glass widget cards (today: just the timeline),
  so more widgets can be added later without restructuring.

### Data flow

The timeline aggregates **client-side** (no backend endpoint): fetch the active receiver's
non-archived trackers, then concurrently fetch each tracker's events for the selected day, merge into
`[EventRef]`, and sort oldest-first (ties broken by `eventId`). The day window is half-open
`[startOfDay, nextMidnight)`. A `.task(id:)` keyed on receiver + day re-runs and auto-cancels the load
when either changes.

## Key decisions

| Decision         | Choice                                                    | Why                                                                                                     |
| ---------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Time scope       | Single day + date navigation, not an infinite feed        | Matches the "review this day" use case; keeps the merge small                                           |
| Data source      | Client-side aggregation (fan-out over existing endpoints) | No backend/contract change; N+1 and merged-stream pagination are negligible at single-day, family scale |
| Visual           | Equal-spaced vertical rail/stepper, earliest at top       | Reads as a clean chronological log; not a to-scale 24h axis                                             |
| Event tap target | Reuse `EventDetailView`                                   | One edit/delete screen, no duplication                                                                  |
| Stale-after-edit | Dedicated `EventRef` nav destination that reloads the day | Avoids the shared-state-after-mutation bug class                                                        |
| Container        | Glass widget card via reusable `.glassCard()`             | Lets the tab grow to multiple widgets later                                                             |
| Render container | Plain `VStack(spacing:0)`, not a `List`                   | Continuous rail, card sizes to content, fixes segmented rail + wrapping time                            |

**Future note:** if a receiver-scoped events endpoint is ever built (`receiver_id + occurred_at` GSI +
`/receivers/{id}/events`), both this timeline and the deferred Home "last reading" card can consume it.
Shared, deferred optimization — see `docs/TECH_DEBT.md`.

## Where it lives

| Concept                                                               | File                                                                                       |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Screen: date-nav header, widget stack, states, `EventRef` destination | `ios/Caregiver/Activity/ActivityView.swift`                                                |
| Load + merge/sort, state machine (`merge` is a pure static fn)        | `ios/Caregiver/Activity/ActivityModel.swift`                                               |
| One timeline step: gutter + rail + content                            | `ios/Caregiver/Activity/ActivityRow.swift`                                                 |
| Pure date math: day bounds, header label, `isDaytime`                 | `ios/Caregiver/Activity/ActivityDay.swift`                                                 |
| Reusable `.glassCard()` modifier                                      | `ios/Caregiver/DesignSystem/Components.swift`                                              |
| Tests (pure units only)                                               | `ios/CaregiverTests/ActivityDayTests.swift`, `ios/CaregiverTests/ActivityMergeTests.swift` |

## Non-goals

- No infinite/continuous feed — single day only.
- No merged-stream pagination — first page per tracker per day is sufficient.
- No per-tracker filter, search, or multi-receiver view.
- No scaled/proportional time axis.
- No future dates.
- No backend changes (no new endpoint, no GSI) — deferred to a future shared slice.
