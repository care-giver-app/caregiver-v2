# Trackers (browse & manage)

- **Module:** ios
- **Status:** Figma design pass **done** (browse frame `71:2`); spec written 2026-07-01 to document the already-built frame and record coherence decisions — next is the SwiftUI build.
- **Last updated:** 2026-07-01
- **Contract:** `listTrackers(receiverId)` → `Tracker{tracker_id,name,kind,fields,icon?,color?,archived}`; per-tracker events via `listEvents(trackerId)` (`shared/openapi/openapi.yaml`). `TrackerKind = event | measurement | scheduled`.
- **Related specs:** [[home]] ("See all" pushes here), [[add-tracker]] (the "New" button target), [[event-detail]] (a tapped event), [[sample-data]] (fixtures + kind-label mapping), [[design-system]]

> Written after the frame was built, to give the Trackers browse screen a living spec and record the
> 2026-07-01 coherence decisions. Documents `71:2`; edit in place as it evolves.

## Purpose

The full list of the active receiver's trackers, reached from Home's "See all (12)". Each row shows the
tracker name, its **kind label**, and its **last logged value + recency**. Admins add trackers here (the
"New" button → [[add-tracker]]); filters segment the list.

## Behavior

- **Header:** back nav + "Trackers" + receiver subtitle ("Eleanor · 12 active") + **New** button (`72:5`,
  admin-only → [[add-tracker]]).
- **Filter chips:** `All · Needs attention · Archived`.
- **Tracker rows:** hue rail + name + kind label + last value + recency (e.g. "Blood pressure · Numeric ·
  128/82 · yesterday"; "Meals · Quick log · no value · **Due**"). Recency-as-luminance per [[design-system]].
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

## Gaps (flagged by the 2026-07-01 review — deferred, not fixed here)

- **Per-tracker detail / history screen** — rows have a chevron but no designed destination (history, edit,
  archive). `getTracker` / `updateTracker` / `archiveTracker` / `listEvents` all exist in the contract.
- **Single-tracker log path** — the only quick-log entry is the multi-tracker ⊕ FAB wizard ([[logging]]);
  there is no "log just this tracker" affordance from a row.
- **Empty / loading / error states** (no trackers yet, load failure) are undesigned in Aurora.

## Where it lives

| Concept                      | Location                                                                     |
| ---------------------------- | ---------------------------------------------------------------------------- |
| Design (lead)                | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Trackers` frame `71:2` |
| "New" entry → Add Tracker    | Trackers `71:2` → `New` `72:5` (see [[add-tracker]])                         |
| iOS screen (to build)        | `ios/Caregiver/Trackers/…`                                                   |
| Tokens (pending Aurora sync) | `ios/Caregiver/DesignSystem/Theme.swift` (see [[design-system]])             |

## Non-goals

- No per-tracker detail/history in this pass (endpoints exist; deferred).
- No tracker edit/archive UI yet (separate flow; `updateTracker`/`archiveTracker` exist).
- `createTracker` is admin-only — caregivers don't see "New".
