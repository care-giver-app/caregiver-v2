# Trackers (browse & manage)

- **Module:** ios
- **Status:** Figma design pass **done** (browse frame `71:2`); **SwiftUI build done** (this branch's PR) (2026-07-05 assembly pass with [[shell]] + [[home]]).
- **Last updated:** 2026-07-05
- **Contract:** `listTrackers(receiverId)` → `Tracker{tracker_id,name,kind,fields,icon?,color?,archived}`; per-tracker events via `listEvents(trackerId)` (`shared/openapi/openapi.yaml`). `TrackerKind = event | measurement | scheduled`.
- **Related specs:** [[home]] ("See all" pushes here), [[shell]] (the pinned tab bar), [[add-tracker]] (the "New" button target), [[event-detail]] (a tapped event), [[sample-data]] (fixtures + kind-label mapping), [[design-system]]

> Written after the frame was built, to give the Trackers browse screen a living spec and record the
> 2026-07-01 coherence decisions. Documents `71:2`; edit in place as it evolves.

## Purpose

The full list of the active receiver's trackers, reached from Home's "See all (12)". Each row shows the
tracker name, its **kind label**, and its **last logged value + recency**. Admins add trackers here (the
"New" button → [[add-tracker]]); filters segment the list.

## Behavior

- **Header:** back nav + "Trackers" + receiver subtitle ("Eleanor · 12 active") + **New** button (`72:5`,
  admin-only → [[add-tracker]]).
- **Filter chips:** `All · Needs attention · Archived`. "Needs attention" = never-logged or 7+ days
  silent (a soft "quiet lately" filter — see decision 6; true "Due" needs B3b).
- **Tracker rows:** hue rail + name + kind label + last value + recency (e.g. "Blood pressure · Numeric ·
  128/82 · yesterday"; "Meals · Quick log · no value · **Due**" (Figma only — "Due" never renders until
  B3b, decision 6)). Recency-as-luminance per [[design-system]].
- Tab bar pinned (Home active in this frame, pushed as a child of Home).

## Backend reality (shapes the design)

- **Kind labels are a client-side affordance.** The rows show `Quick log / Count / Checklist / Scale /
Numeric / Duration`, but the contract's `kind` is only `event | measurement | scheduled`. The friendly
  label is **derived** from `kind` + the field schema — see the mapping table in [[sample-data]]. [[add-tracker]]
  shows the raw `kind` badge instead; both must agree via that mapping.
- Last value + recency aggregate client-side from `listEvents` (first page per tracker), like [[home]].

## Key decisions

| #   | Decision                    | Choice                                                                                              | Why                                                                                                                             |
| --- | --------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Kind label vocabulary       | Show the **derived friendly label**; document its `kind`+`Field.type` derivation in [[sample-data]] | Coherence review 2026-07-01: Trackers used 6 labels while [[add-tracker]] showed 3 contract kinds and [[insights]] a third set. |
| 2   | Sample data / roster + hues | Bind to the canonical **[[sample-data]]** roster; one hue per tracker across all screens            | Review found the visible tracker set drifting between Home/Trackers and Insights, and hues swapping.                            |
| 3   | Row tap target              | **Undesigned — flagged gap** (see below)                                                            | The chevron implies a per-tracker detail/history destination that no frame covers yet.                                          |
| 4   | Row tap interim             | Push the existing (pre-Aurora) `TrackerDetailView` via `Route.tracker`                              | 2026-07-05: history/edit/archive is real, working functionality; keep it reachable until a designed replacement exists.         |
| 5   | List data                   | Shared **`TrackerSummariesModel`** with [[home]]; keeps archived trackers (for the Archived chip)   | 2026-07-05: one derivation for last value / recency / kind label across both screens; see [[home]] decision 6.                  |
| 6   | "Needs attention" semantics | Never-logged or **7+ days silent**; the amber "Due" state is not produced until B3b                 | 2026-07-05 (Trevor): no cadence in the contract — [[home]] decision 8. A quiet-lately filter makes no false "Due" claim.        |

## Gaps (flagged by the 2026-07-01 review — deferred, not fixed here)

- **Per-tracker detail / history screen** — rows have a chevron but no designed destination (history, edit,
  archive). `getTracker` / `updateTracker` / `archiveTracker` / `listEvents` all exist in the contract.
- **Single-tracker log path** — the only quick-log entry is the multi-tracker ⊕ FAB wizard ([[logging]]);
  there is no "log just this tracker" affordance from a row.
- **Empty / loading / error states** (no trackers yet, load failure) are undesigned in Aurora.

## Where it lives

| Concept                   | Location                                                                         |
| ------------------------- | -------------------------------------------------------------------------------- |
| Design (lead)             | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Trackers` frame `71:2`     |
| "New" entry → Add Tracker | Trackers `71:2` → `New` `72:5` (see [[add-tracker]])                             |
| iOS screen                | `ios/Caregiver/Trackers/TrackersView.swift` (this pass)                          |
| Shared summaries model    | `ios/Caregiver/Trackers/TrackerSummariesModel.swift` (this pass)                 |
| Tokens                    | `ios/Caregiver/DesignSystem/Theme.swift` — Aurora-synced (see [[design-system]]) |

## Non-goals

- No per-tracker detail/history in this pass (endpoints exist; deferred).
- No tracker edit/archive UI yet (separate flow; `updateTracker`/`archiveTracker` exist).
- `createTracker` is admin-only — caregivers don't see "New".
