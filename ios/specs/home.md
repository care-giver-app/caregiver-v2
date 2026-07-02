# Home

- **Module:** ios
- **Status:** Figma design pass **done** (landing frame `53:3`); spec written 2026-07-01 to document the already-built frame and record coherence decisions — next is the SwiftUI build.
- **Last updated:** 2026-07-01
- **Contract:** `listReceivers`, `listTrackers(receiverId)`, `listEvents(trackerId, from:, to:)`, `listMembers(careGroupId)` (`shared/openapi/openapi.yaml`). **No appointments/schedule endpoint exists** — see Backend reality.
- **Related specs:** [[receivers]] (the header switcher opens the switch sheet), [[trackers]] ("See all" target), [[logging]] (the ⊕ FAB), [[activity-timeline]] (the Today timeline widget), [[insights]] · [[team]] · [[settings]] (sibling tabs), [[sample-data]] (fixtures), [[design-system]] (Stride system)

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
  subtitle + caregiver face-pile. Tapping the chevron opens the [[receivers]] switch sheet. Fixtures per
  [[sample-data]]: receiver **Eleanor**, group **The Riverside Group**, face-pile **T · D · M**.
- **"Coming up" banner** (`64:2`) — e.g. "Cardiology check-up · in 9 days". **Design-ahead** (see below).
- **Tracker snapshot** — a grid of the receiver's trackers showing each tracker's **last logged event**
  (req 3), with recency-as-luminance (cyan = fresh, dim = stale, amber "Due" = overdue). "See all (12)"
  pushes [[trackers]]. Snapshot trackers are a subset of the canonical [[sample-data]] roster and should
  overlap [[insights]] on the headline trackers (BP / Medication / Pain).
- **Today timeline** — the single-day cross-tracker stepper from [[activity-timeline]], embedded as a Home
  widget (it is **not** a separate tab). Tapping an event → [[event-detail]].
- **⊕ FAB** → [[logging]] quick-log wizard. **Tab bar** → Insights / Team / Settings.

## Backend reality (shapes the design)

- **Appointments have no contract.** There is no `Appointment` or `Schedule` entity/endpoint in
  `shared/openapi/openapi.yaml` (B3b — Schedules — is unbuilt). The **"Coming up" banner is designed ahead
  of the contract** and must be flagged as such. It pairs with the [[settings]] "Appointment reminders"
  toggle (also B3b design-ahead).
- **Requirements 4 & 5 are only partly covered.** The banner is a partial answer to req 5 ("in-app
  indication for appointments within 2 weeks"); **req 4 ("view upcoming _and past_ appointments") is
  entirely undesigned** — no list, detail, or create flow. See Gaps.
- Everything else on Home aggregates client-side from the listed endpoints (same fan-out as
  [[activity-timeline]]); no Home-specific endpoint.

## Key decisions

| #   | Decision                     | Choice                                                                                         | Why                                                                                                                                               |
| --- | ---------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Home merges Today + snapshot | One landing tab: header + banner + tracker snapshot + Today timeline widget                    | The post-login IA is 4 tabs; the standalone Activity tab folded into Home as a widget.                                                            |
| 2   | Sample data                  | Bind to **[[sample-data]]** — Eleanor / **The Riverside Group** / face-pile **T · D · M**      | Coherence review 2026-07-01: Home said "Mom's Care Team" (vs Settings' active group) and drew a `D · S · +2` face-pile against a 3-person roster. |
| 3   | Appointment banner honesty   | Keep the banner but **flag it design-ahead** (B3b); do not fake a tap-through to a list/detail | No `Appointment`/`Schedule` in the contract; honesty rule.                                                                                        |

## Gaps (flagged by the 2026-07-01 review — deferred, not fixed here)

- **Appointments (reqs 4–5):** no upcoming/past **list**, no **detail**, no **create**; no contract entity.
  Needs a dedicated **appointments spec + B3b design pass** (Bucket B). The banner is the only surface today.
- **Empty / loading / error states** for the snapshot + timeline are undesigned in Aurora.

## Where it lives

| Concept                           | Location                                                                          |
| --------------------------------- | --------------------------------------------------------------------------------- |
| Design (lead)                     | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Home` frame `53:3`          |
| Receiver switcher trigger         | Home `53:3` → `ReceiverSwitcher` `54:4` (opens [[receivers]])                     |
| "Coming up" banner (design-ahead) | Home `53:3` → banner `64:2`                                                       |
| iOS screen (placeholder/partial)  | `ios/Caregiver/Home/…`                                                            |
| Today timeline widget             | `ios/Caregiver/Activity/…` (see [[activity-timeline]])                            |
| Tokens (pending Aurora sync)      | `ios/Caregiver/DesignSystem/Theme.swift` — still old blue (see [[design-system]]) |

## Non-goals

- No appointments list/detail/create in this pass — deferred to a B3b appointments spec (banner only).
- No per-tracker history on Home — "See all" → [[trackers]]; a single event → [[event-detail]].
- No multi-receiver view — Home is scoped to the one active receiver.
