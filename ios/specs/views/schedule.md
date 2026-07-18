# Schedule look-ahead ("Coming up")

- **Module:** ios
- **Status:** Figma design pass **done** (list `219:986`, empty `223:1051`); **SwiftUI build done** (2026-07-16, this branch).
- **Last updated:** 2026-07-16
- **Contract:** `listReceiverScheduledItems(receiverId, from:, to:, limit:, cursor:)` → `ScheduledItemList` (soonest-first, cross-tracker), `listTrackers(receiverId)` for the name/hue join (`shared/openapi/openapi.yaml` → `/receivers/{id}/scheduled-items`, `/receivers/{id}/trackers`). No contract changes — the B3b scheduled-items surface already exists.
- **Related specs:** [[home]] (hosts the entry-point banner), [[design-system]] (`StrideComingUpBanner`, `StrideTrackerRow`, `StrideSectionHeader`), [[sample-data]] (upcoming-item fixtures), [[trackers]] (row tap destination)

> Living spec for the iOS schedule look-ahead. This is the surface that revives the Home "Coming up"
> banner (long design-ahead) against the now-real scheduled-items contract, and answers the deferred
> [[home]] "upcoming appointments" gap (req 5).

## Purpose

Answer "what's coming up for this person?" A caregiver sees the single soonest scheduled item on
[[home]] (a banner), and can tap through to a full, grouped list of everything scheduled ahead. Purely
a **read-only look-ahead** — no create/edit, no past view.

## Behavior

- **Entry point — the Home banner.** `StrideComingUpBanner` (Figma `64:2`) sits between the Home header
  and the tracker snapshot. It shows the **soonest** upcoming item (title = tracker name, amber relative
  label like "in 9 days"), and renders **only when there is one** — no banner when the receiver has
  nothing scheduled (never a broken/empty pill). Tapping pushes the list.
- **The list (`ScheduleView`).** Upcoming items **soonest-first**, grouped into two sections —
  **This week** (`< 7` calendar days) and **Later** — each a `StrideSectionHeader` over `StrideTrackerRow`s
  (hue rail = tracker hue, name, note subtitle, **relative label in the trailing meta slot**, chevron).
  Only non-empty sections render. Tapping a row → the tracker's [[trackers]] detail (`Route.tracker`).
- **Relative label** (shared `ScheduleTime`): `Overdue` / `Today` / `Tomorrow` / `in N days` — always
  relative within the window, never an absolute date (mirrors the Figma frame).
- **States:** `loading` (spinner), `empty` ("No upcoming items."), `error` (retry) via the standard
  Stride state views. The banner is the empty state on Home (hidden); the list owns the explicit empty.

## Data flow

One shared **`ScheduleModel`** owns the load and feeds both surfaces (Home holds the instance; the
pushed `ScheduleView` reads the same one — a single fetch, no double load). `load` fetches the active
receiver's trackers and `listReceiverScheduledItems(from: now, to: now + 60d, limit: 100)`
(**receiver-scoped, so no client-side fan-out** — unlike [[activity-timeline]]), then joins each item
to its tracker for name + hue, dropping items whose tracker is missing or archived, preserving the
server's soonest-first order. A `.task(id:)` on Home keyed on the active receiver drives it (loaded
alongside the tracker summaries).

## Key decisions

| Decision               | Choice                                                                               | Why                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| Scope                  | Read-only, **future-only** (`from = now`, 60-day window), soonest-first              | Smallest honest surface that covers [[home]] req 5; past/create is a later B3b pass.                      |
| Two surfaces, one load | Home banner (soonest) + pushed list (all), fed by one shared `ScheduleModel`         | Avoids a double fetch; the banner is just `items.first`.                                                  |
| Buckets                | **This week** (`< 7d`) / **Later**; render only non-empty                            | Matches the approved Figma frame; calendar-day math (not 7×24h) so "in 6 days" lands in the right group.  |
| Row component          | Reuse `StrideTrackerRow` — relative label in the **meta** slot, note in the subtitle | 1:1 with the existing Trackers row; no new component (no Section-Header/upcoming-row component exists).   |
| Emphasis               | All rows **calm** (grey meta); amber reserved for the banner                         | 2026-07-16 (Trevor, "looks fine"): the app leans calm; the banner is the one attention cue.               |
| Row tap                | → existing `TrackerDetailView` via `Route.tracker`                                   | The scheduled item's tracker is the natural destination; no new scheduled-item detail screen this pass.   |
| Chrome                 | Pushed screen uses system `.navigationTitle("Coming up")` + back button              | Matches `TrackerDetailView`; the Figma frame's custom title/back is the mock's rendering of nav chrome.   |
| Subtitle source        | `note` only (blank → omitted); not the item `values`                                 | `ScheduledItem.values` is a different generated type than `Event.values`; note carries the useful detail. |

## Gaps

- **Past scheduled items** and a **create/edit/reschedule** flow are undesigned (the contract supports
  `createScheduledItem`/`updateScheduledItem`/`deleteScheduledItem`, but no UI yet).
- **Soon/overdue emphasis** is deliberately off (calm rows). If wanted later, `StrideTrackerRow`'s
  `.overdue` variant (amber rail + "Soon" `StrideBadge`) can flag items within ~24h.
- **Pagination:** first page (`limit: 100`) only — the 60-day family-scale window fits well within it;
  `next_cursor` is ignored (same posture as [[activity-timeline]]).
- The standalone Figma banner frame `64:2` text should be refreshed to the soonest fixture item (see
  [[sample-data]] drift note).

## Where it lives

| Concept                                             | Location                                                                                                             |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Design (list / empty)                               | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** → `Coming Up` `219:986`, `Coming Up · Empty` `223:1051`; banner `64:2` |
| Banner component                                    | `ios/Caregiver/DesignSystem/StrideComingUpBanner.swift`                                                              |
| List screen                                         | `ios/Caregiver/Schedule/ScheduleView.swift`                                                                          |
| Load + join, `map` (pure static fn), `UpcomingItem` | `ios/Caregiver/Schedule/ScheduleModel.swift`                                                                         |
| Relative label + bucketing (pure)                   | `ios/Caregiver/Schedule/ScheduleTime.swift`                                                                          |
| Home integration (banner + push + load)             | `ios/Caregiver/Home/HomeView.swift`                                                                                  |
| Tests (pure units)                                  | `ios/CaregiverTests/ScheduleTimeTests.swift`, `ios/CaregiverTests/ScheduleModelTests.swift`                          |

## Non-goals

- No past/history view, no create/edit/reschedule/delete UI — read-only, future-only.
- No client-side fan-out — the receiver-scoped endpoint returns the merged list.
- No merged-stream pagination — first page over a 60-day window is sufficient.
- No per-tracker filter or multi-receiver view — scoped to the one active receiver.
