# Design Review Brief — CareToSher (Stride) iOS

> **How to use this:** open this file as the opening prompt in a **fresh Claude Code session**. You are
> reviewing the Figma design pass for the CareToSher iOS app (project "Stride"). Produce a **written,
> ranked findings report**. Do **not** implement code and do **not** rewrite the specs — _flag_ issues
> for triage. Work with clean eyes; the previous session authored these designs, so do not assume its
> decisions were right.

## Priority order — lead with #1

1. **Design coherence + gap analysis** (PRIMARY) — do the screens read as one product, and what flows/states are missing?
2. **Spec ↔ contract fidelity** — do the living specs match Figma and the OpenAPI contract; is every design-ahead item honestly flagged?
3. **Figma hygiene** — component-API consistency, variant coverage, naming.

Spend most of the effort on #1. It is the cheapest to fix now (it is still just Figma) and gaps compound if we build on them.

## Inputs to load first

- **Living specs:** `ios/specs/insights.md`, `ios/specs/team.md`, `ios/specs/settings.md`, `ios/specs/receivers.md`, `ios/specs/add-tracker.md` (and `ios/specs/activity-timeline.md` if present). Each spec's **"Where it lives"** section has the Figma **node-ID table**.
- **Requirements:** `WORKING.md` (the source requirements list).
- **Contract:** `shared/openapi/openapi.yaml` (the module interface — specs must not contradict it).
- **Orientation:** `CLAUDE.md`, `docs/roadmap.md`.
- **Figma:** file key `qoiOteGuzktJPB6WKRbGHt`, page **App Flow**. Use the Figma MCP (`get_screenshot`, `get_metadata`) to pull each frame by the node IDs in the specs. The reusable component library lives in the **Components** board (moved to the far right, x≈2120).

## Design substrate (so you evaluate against the intended system)

- **Palette:** live "Aurora" cyan-on-navy — bind to `aurora/*` + `color/auth/*`. ⚠️ `color/*` is **stale** (old blue) — flag any usage.
- **Type:** Space Grotesk (display) + Inter (body); ramp 28→22→16→14→13→12.
- **Surfaces:** glass cards radius 16, 1px border; two blurred **Aurora Glow** ellipses bleeding from the top; vertical `#050b2e→#0a1640` gradient bg.
- **Signature:** _recency-as-luminance_ — cyan glow on fresh/active, dim when stale, amber "Due" when overdue.
- **Patterns:** bottom **sheet** (grabber + title + content) for modals/pickers; full-screen **wizard** (back + 2-dot step indicator, no tab bar) for multi-step; section-header labels; monogram avatars (no photo field anywhere); per-entity **hue** where it aids recognition (tracker hues cyan/teal/violet).
- **Honesty rule:** designs that run ahead of the contract must be flagged as design-ahead, never faked.

## The design surface (frames to review — file `qoiOteGuzktJPB6WKRbGHt`, page App Flow)

| Flow                     | Frame(s)                                | Node ID(s)              |
| ------------------------ | --------------------------------------- | ----------------------- |
| Home (landing)           | `Home`                                  | `53:3`                  |
| Trackers (browse/manage) | `Trackers`                              | `71:2`                  |
| Logging (quick-log)      | wizard section (Select → Mood → Pain)   | section `84:2`          |
| Insights                 | overview + BP detail                    | `119:197`, `119:375`    |
| Team                     | overview + invite sheet                 | `146:415`, `150:484`    |
| Settings                 | main (scroll) + create-care-group sheet | `159:585`, `161:665`    |
| Receivers                | switch sheet + add sheet                | `168:751`, `170:852`    |
| Add Tracker              | choose-template + configure             | `176:939`, `177:982`    |
| Component library        | Components board (Stride/\*)            | section `84:4` (x≈2120) |

## Requirements coverage (from `WORKING.md`) — verify each, find the uncovered

| #   | Requirement                                    | Intended screen                   | Status to verify |
| --- | ---------------------------------------------- | --------------------------------- | ---------------- |
| 1   | Add one or more tracking events at a time      | Logging quick-log wizard `84:2`   | covered?         |
| 2   | View a daily timeline of events                | Home Today Timeline `53:3`        | covered?         |
| 3   | View last logged event per tracker on one view | Home snapshot / Trackers          | covered?         |
| 4   | View upcoming **and past** appointments        | — only Home "Coming up" banner    | **likely GAP**   |
| 5   | In-app indication for appts within 2 weeks     | Home "Coming up" banner `64:2`    | partial?         |
| 6   | Trend per tracker (count per timeframe)        | Insights `119:197`                | covered?         |
| 7   | Scatter: hour-of-day × date                    | Insights scatter                  | covered?         |
| 8   | Adjust timeframe for charts/stats              | Insights timeframe selector       | covered?         |
| 9   | Graphs for numeric trackers (value vs time)    | Insights line                     | covered?         |
| 10  | Quick-log events requiring no data             | Logging / event trackers          | verify           |
| 11  | See other caregivers in group                  | Team `146:415`                    | covered?         |
| 12  | See the active care receiver                   | Home header `54:4`                | covered?         |
| 13  | Change the care receiver                       | Receivers switch `168:751`        | covered?         |
| 14  | Invite another caregiver                       | Team invite `150:484`             | covered?         |
| 15  | Create a tracker                               | Add Tracker `176:939` / `177:982` | covered?         |
| 16  | See all event data for a specific event        | — (no event-detail frame)         | **GAP**          |
| 17  | Edit and delete events                         | — (no event-detail frame)         | **GAP**          |

## Known gaps to confirm and prioritize (not yet designed)

- **Event detail / edit / delete** (reqs 16–17) — `updateEvent` / `deleteEvent` exist in the contract; no frame designed.
- **Appointments / schedules** (req 4, B3b) — only the Home "Coming up" banner exists; no list/detail/create.
- **Empty / loading / error states** across every screen — largely absent (Insights has an empty-card pattern; others don't).
- **Single-tracker log** vs the multi-tracker quick-log wizard — confirm both paths are covered.
- **Custom tracker** (blank config) — deferred; only the Custom _card_ exists.
- **Accessibility** — contrast ratios on tertiary text/hue washes, 44pt touch targets, Dynamic Type reflow, VoiceOver labels.

## Method

Review **one flow at a time**. For each: pull the screenshot(s), read the matching spec, check against `WORKING.md` + the contract, and note any deviation from the design substrate/patterns above (drift between screens is a finding). Prefer evidence — cite node IDs and spec lines.

## Output format

Produce a markdown report:

1. **Top 5** to fix first (one line each).
2. **Findings table:** `# | Severity (high/med/low) | Area (screen/component) | Finding | Why it matters | Suggested fix | Figma node`.
3. **Gap list:** missing flows/states, prioritized.
4. **Consistency deviations:** patterns that drift across screens.

Keep it evidence-based. No vibes.

## Out of scope for this pass

- SwiftUI implementation — that's the vertical-slice step _after_ triage.
- Rewriting specs — flag, don't fix.
- The `ios/Caregiver/DesignSystem/Theme.swift` **old-blue divergence is already known and tracked** — do not re-report it as a new finding.
