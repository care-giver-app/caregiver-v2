# Logging (quick-log wizard)

- **Module:** ios
- **Status:** Built (2026-07-06) — wizard live behind the ⊕ FAB; interim QuickLogSheet deleted. Single-tracker entry + breach surfacing still deferred.
- **Last updated:** 2026-07-06
- **Contract:** `logEvent(trackerId, EventWrite{values, occurred_at?, note?})` → `Event` (`shared/openapi/openapi.yaml`); `listTrackers(receiverId)` to populate the picker. Editing a logged event reuses this via [[event-detail]] (`updateEvent`).
- **Related specs:** [[home]] (the ⊕ FAB opens this), [[trackers]] (the tracker source), [[event-detail]] (edit reuses the same input), [[sample-data]] (fixtures), [[design-system]]

> Written after the frames were built, to give the logging flow a living spec and record the 2026-07-01
> coherence decisions. Documents the `84:2` wizard section; edit in place as it evolves.

## Purpose

Log **one or more** events in a single pass (req 1), including **quick-log events that need no data**
(req 10). Reached from the ⊕ FAB on any tab. A bottom-sheet wizard: pick trackers → fill only the ones
that need values → submit.

## Behavior

A **bottom-sheet wizard** over the dimmed current tab (grabber + scrim + step-dot indicator; the frames
show a ~3/4-height sheet — decision 7):

- **Step 0 — pick trackers.** "Log events for <receiver> · Now ▾" + a multi-select list of the receiver's
  trackers (checkable). A footer counts how many selected trackers **need details** ("2 of 4 trackers need
  details"). `Next`. `occurred_at` defaults to **Now** (`EventWrite.occurred_at`), adjustable.
- **Detail steps** — one per selected tracker **that has value fields**; quick-log/no-value trackers
  (Meals, Hydration count) are skipped. Each step matches the field kind (Mood = 1–5 scale; Pain = 0–10
  slider; numeric = keypad). "Add a note (optional)" maps to `EventWrite.note`. Step indicator shows
  `Step n of N`.
- **Submit** — there is no separate confirm screen: the **last detail step's** primary button (or the
  select step's, when nothing needs details) reads "**Log N events**" and posts one `logEvent` per
  selected tracker (concurrently).
- **Results / partial failure** — after submit, the confirm step shows per-tracker results: succeeded
  trackers lock in (never repost), failed ones show the error with a single **Retry failed** button that
  reposts only the failures. A fully successful submit dismisses the wizard and refreshes Home via the
  existing `logVersion` token ([[shell]]).
- **Load states** — step 0's tracker fetch uses the standard Stride state views (`StrideLoadingView` /
  `StrideErrorState` / `StrideEmptyState`), matching the rest of the app.

Fixtures per [[sample-data]]: receiver **Eleanor**, trackers from the canonical roster (the wizard's picker
must draw from the same roster as [[home]]/[[trackers]] — the review found "Walk" appearing here but not on
Trackers).

## Backend reality (shapes the design)

- **One `logEvent` per tracker** — there is no batch endpoint; "Log 4 events" fans out to 4 POSTs. Note as a
  client concern (partial-failure handling) for the build.
- **`values` is an open map** (`additionalProperties`) keyed by `Field.key`; quick-log no-value events post
  an empty/minimal `values` object.
- `breaches[]` may come back on the created `Event` (threshold hits) — surfacing them is deferred (see
  [[event-detail]] breach note).

## Key decisions

| #   | Decision                    | Choice                                                                                                                    | Why                                                                                                            |
| --- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| 1   | Multi-log model             | Full-screen wizard: multi-select → per-tracker detail steps → "Log N events"                                              | Covers reqs 1 + 10 in one pass; matches the [[add-tracker]] wizard pattern.                                    |
| 2   | Quick-log no-value          | Selected no-value trackers are logged directly (skipped in detail steps)                                                  | Req 10 — some events need no data.                                                                             |
| 3   | Sample data / picker roster | Bind to the canonical **[[sample-data]]** roster                                                                          | Coherence review 2026-07-01: the picker showed "Walk", absent from the [[trackers]] list.                      |
| 4   | Single-tracker log          | **Undesigned — flagged gap** (see below)                                                                                  | Only the multi-tracker FAB path exists.                                                                        |
| 5   | Partial-failure handling    | Per-tracker results on the confirm step + **Retry failed** (reposts failures only)                                        | 2026-07-06: no batch endpoint, so N POSTs can partially fail; succeeded posts must never duplicate.            |
| 6   | Load / error states         | Standard Stride state views on step 0's tracker fetch                                                                     | 2026-07-06: follow the app-wide convention rather than bespoke Aurora states.                                  |
| 7   | Presentation                | Bottom sheet (~3/4 height, grabber + scrim + step dots), not full-screen                                                  | 2026-07-06 build: frames `75:2`/`80:2`/`81:2` all show a sheet over the dimmed tab; spec corrected.            |
| 8   | Field input mapping         | enum → scale tiles; number → keypad; bool → stride toggle; text/datetime → field/picker. Figma's pain **slider deferred** | `Field` has no min/max in the contract, so a bounded slider can't be data-driven (bounded-number ledger item). |

## Gaps (flagged by the 2026-07-01 review)

- **Single-tracker quick-log** — no "log just this tracker" entry from a Home snapshot card or [[trackers]]
  row; the wizard is the only path. Deferred.
- ~~Loading / error / partial-failure states~~ — resolved 2026-07-06 (decisions 5–6).

## Where it lives

| Concept                      | Location                                                                                           |
| ---------------------------- | -------------------------------------------------------------------------------------------------- |
| Design (lead)                | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Logging` section `84:2`                      |
| Entry point                  | The ⊕ FAB on the tab bar ([[home]] and siblings)                                                   |
| iOS screen                   | `ios/Caregiver/Logging/` (QuickLogWizardView + steps; edit path still event-detail's LogEventView) |
| Tokens (pending Aurora sync) | `ios/Caregiver/DesignSystem/Theme.swift` (see [[design-system]])                                   |

## Non-goals

- No single-tracker log entry in this pass (deferred).
- No batch/transactional log endpoint — client fans out per tracker.
- No breach surfacing on log confirm — deferred (see [[event-detail]]).
