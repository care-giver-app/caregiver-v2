# Home

- **Module:** ios
- **Status:** Figma design pass **done** (landing frame `53:3`); **SwiftUI build done** (2026-07-05 assembly pass with [[shell]] + [[trackers]]). **"Coming up" banner + [[schedule]] look-ahead built** against the B3b scheduled-items contract (2026-07-16).
- **Last updated:** 2026-07-16
- **Contract:** `listReceivers`, `listTrackers(receiverId)`, `listEvents(trackerId, from:, to:)`, `listMembers(careGroupId)`, `listReceiverScheduledItems(receiverId, from:, to:)` (`shared/openapi/openapi.yaml`). The scheduled-items surface now exists (B3b) — see [[schedule]].
- **Related specs:** [[shell]] (the tab frame hosting Home), [[receivers]] (the header switcher opens the switch sheet), [[trackers]] ("See all" target), [[logging]] (the ⊕ FAB), [[activity-timeline]] (the Today timeline widget), [[insights]] · [[team]] · [[settings]] (sibling tabs), [[sample-data]] (fixtures), [[design-system]] (Stride system)

> This spec was written **after** the Home frame was built, to give the app's spine a living spec (it had
> none) and to house the coherence decisions from the 2026-07-01 review. It documents the current intended
> state of `53:3`; edit in place as Home evolves.

## Purpose

Home is the landing tab — "how is <receiver> right now?" It composes four stacked regions for the active
receiver: the **receiver switcher header**, a **"Coming up" appointment banner**, a **tracker snapshot**
(last logged per tracker), and the **Today timeline** (the [[activity-timeline]] widget). The ⊕ FAB opens
quick-log; the tab bar switches to Insights/Team/Settings.

## Behavior

- **Receiver switcher header** (`54:4`) — monogram + active receiver name + `chevron.down` + care-group
  subtitle + caregiver face-pile. Tapping the chevron opens the [[receivers]] switch sheet (**interim:**
  the existing switcher `Menu` until the switch-sheet pass — decision 5). Fixtures per
  [[sample-data]]: receiver **Eleanor**, group **The Riverside Group**, face-pile **T · D · M**.
- **"Coming up" banner** (`64:2`) — `StrideComingUpBanner` showing the single soonest upcoming scheduled
  item (e.g. "Cardiology check-up · in 9 days"), amber relative label. Renders only when the active
  receiver has an upcoming item; tapping pushes the [[schedule]] look-ahead list (decision 9). Data via
  the shared **`ScheduleModel`** (`listReceiverScheduledItems`, soonest-first).
- **Tracker snapshot** — a 2-column grid of up to **6 `StrideTrackerTile`s, attention-first** (overdue
  first, then stalest), each showing the tracker's **last logged event** (req 3) with
  recency-as-luminance (cyan = fresh, dim = stale, amber "Due" = overdue) (design layer only — never
  rendered until B3b, decision 8). "See all (12)"
  pushes [[trackers]]. Snapshot trackers are a subset of the canonical [[sample-data]] roster and should
  overlap [[insights]] on the headline trackers (BP / Medication / Pain). Data comes from the shared
  **`TrackerSummariesModel`** (decision 6).
- **Today timeline** — the single-day cross-tracker stepper from [[activity-timeline]], embedded as a Home
  widget (it is **not** a separate tab). Tapping an event → [[event-detail]].
- **⊕ FAB** → [[logging]] quick-log wizard. **Tab bar** → Insights / Team / Settings.

## Backend reality (shapes the design)

- **Scheduled items now have a contract (B3b).** `shared/openapi/openapi.yaml` exposes the scheduled-items
  surface, including `listReceiverScheduledItems(receiverId, from:, to:)` (cross-tracker, soonest-first).
  The banner and the [[schedule]] look-ahead read it live — the earlier "design-ahead / do not build"
  posture (decisions 3–4) is retired. Still pairs with the [[settings]] "Appointment reminders" toggle
  (its notification-preferences contract remains B3b-pending).
- **Requirement 5 (upcoming) is covered; req 4 (past) is not.** The banner + [[schedule]] list answer
  "upcoming scheduled items" (`from = now`). **Past scheduled items and a create/edit flow are still
  undesigned** — the look-ahead is read-only, future-only. See Gaps.
- Everything else on Home aggregates client-side from the listed endpoints (same fan-out as
  [[activity-timeline]]); no Home-specific endpoint.

## Key decisions

| #   | Decision                     | Choice                                                                                                                                           | Why                                                                                                                                                                                    |
| --- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Home merges Today + snapshot | One landing tab: header + banner + tracker snapshot + Today timeline widget                                                                      | The post-login IA is 4 tabs; the standalone Activity tab folded into Home as a widget.                                                                                                 |
| 2   | Sample data                  | Bind to **[[sample-data]]** — Eleanor / **The Riverside Group** / face-pile **T · D · M**                                                        | Coherence review 2026-07-01: Home said "Mom's Care Team" (vs Settings' active group) and drew a `D · S · +2` face-pile against a 3-person roster.                                      |
| 3   | Appointment banner honesty   | ~~Flag design-ahead; no tap-through~~ **Superseded by #9** (contract now exists)                                                                 | No `Appointment`/`Schedule` in the contract; honesty rule. (Held until B3b shipped.)                                                                                                   |
| 4   | Banner in the SwiftUI build  | ~~Omit entirely until B3b~~ **Superseded by #9** — banner + list now built on live data                                                          | 2026-07-05 (Trevor): no data can feed it. Retired 2026-07-16 once scheduled-items shipped.                                                                                             |
| 5   | Switcher interim behavior    | Header is rebuilt to the frame, but tapping keeps the existing switcher `Menu`                                                                   | 2026-07-05: the designed switch **sheet** ([[receivers]]) is its own later pass; the menu is real, working functionality.                                                              |
| 6   | Snapshot data                | Shared **`TrackerSummariesModel`** (`listTrackers` + first-page `listEvents` per tracker)                                                        | 2026-07-05: Home's tiles and [[trackers]]' rows need identical last-value/recency/kind-label derivation — one model prevents drift.                                                    |
| 7   | Today timeline widget        | Reuse `ActivityModel`/`ActivityDay` aggregation; render via `StrideTimeline` nodes                                                               | 2026-07-05: the earthy `ActivityView` list dies, but its tested single-day fan-out logic is exactly what the widget needs.                                                             |
| 8   | Recency derivation           | **fresh** = logged within 24h, **normal** = otherwise; `.overdue`/"Due" still not produced on snapshot tiles                                     | 2026-07-05 (Trevor): the _tracker snapshot_ has no cadence to key off. B3b scheduled-items live on the [[schedule]] surface, not the last-event tiles, so the tiles stay fresh/normal. |
| 9   | Banner built on live data    | Build `StrideComingUpBanner` + the [[schedule]] look-ahead against `listReceiverScheduledItems`; banner shows the soonest item, hidden when none | 2026-07-16: B3b scheduled-items shipped a real contract, retiring the design-ahead posture (#3–#4). Live data, no fixtures for real users.                                             |
| 10  | Look-ahead scope             | Read-only, **future-only** (`from = now`, 60-day window), soonest-first; row tap → tracker detail; no create/edit or past view                   | 2026-07-16: covers req 5 (upcoming) with the smallest honest surface; past/create is a later B3b pass ([[schedule]] Gaps).                                                             |

## Gaps (flagged by the 2026-07-01 review — deferred, not fixed here)

- **Upcoming (req 5): done** — banner + [[schedule]] look-ahead. **Past scheduled items (req 4) and a
  create/edit flow remain undesigned** (the look-ahead is future-only, read-only). See [[schedule]] Gaps.
- **Empty / loading / error states** for the snapshot + timeline are undesigned in Aurora. ([[schedule]]
  defines its own: banner hidden when empty; list shows "No upcoming items".)

## Where it lives

| Concept                   | Location                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------- |
| Design (lead)             | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Home` frame `53:3`                                |
| Receiver switcher trigger | Home `53:3` → `ReceiverSwitcher` `54:4` (opens [[receivers]])                                           |
| "Coming up" banner        | Home `53:3` → banner `64:2`; `ios/Caregiver/DesignSystem/StrideComingUpBanner.swift` (see [[schedule]]) |
| iOS screen                | `ios/Caregiver/Home/HomeView.swift` (Aurora rebuild, this pass)                                         |
| Shared summaries model    | `ios/Caregiver/Trackers/TrackerSummariesModel.swift` (this pass)                                        |
| Today timeline widget     | `ios/Caregiver/Activity/…` (see [[activity-timeline]])                                                  |
| Tokens                    | `ios/Caregiver/DesignSystem/Theme.swift` — core values Aurora-synced (see [[design-system]])            |

## Non-goals

- No past-appointments view or create/edit flow — the [[schedule]] look-ahead is upcoming-only, read-only.
- No per-tracker history on Home — "See all" → [[trackers]]; a single event → [[event-detail]].
- No multi-receiver view — Home is scoped to the one active receiver.
