# Insights

- **Module:** ios
- **Status:** Figma design pass **done** (overview + BP detail frame + chart component library) — next is the SwiftUI build
- **Last updated:** 2026-06-30
- **Contract:** `listTrackers(receiverId)`, `listEvents(trackerId, from:, to:)` (`shared/openapi/openapi.yaml`). **No analytics endpoints exist** — aggregate client-side over a timeframe, exactly like [[activity-timeline]].
- **Related specs:** [[activity-timeline]] (client-side aggregation pattern), [[design-system]] (Stride design system), [[caretosher-post-login-ia]] (post-login IA + Figma component library)

> **Read this before building Insights.** It captures the design substrate (palette, type, components,
> file IDs) so you don't re-derive it, the requirements, and the **open design decisions** to resolve
> in the brainstorm/design pass. The current `ios/Caregiver/Insights/InsightsView.swift` is a
> placeholder ("Insights coming soon"). Design happens first in the **CareToSher Figma file**, then
> leads the SwiftUI build.

## Purpose

The **Insights** tab answers _"how is <receiver> trending over time?"_ — per-tracker trends, when-events-happen
distributions, and value-over-time — with a **timeframe the caregiver can adjust**. It complements
[[activity-timeline]] (what happened on one day) and Home (current state at a glance) with the
longitudinal view neither can give.

## Requirements (from `WORKING.md`)

1. **Count trend per tracker** — number of times logged per timeframe.
2. **Hour-of-day × date scatter** — y = hour of day, x = date (shows _when_ in the day events happen / adherence pattern).
3. **Value-vs-time line** — for numeric trackers (e.g. BP, weight, pain), value over time.
4. **Adjustable timeframe** — one control governs any/all charts and stats.

## Behavior (proposed — confirm in the design pass)

A scrollable analytics screen for the active receiver, on the standard 393×852 Aurora frame, **Insights tab active**.

- A **timeframe control** (sticky near the top) drives every chart: e.g. `Week · Month · 3M · Year · Custom`.
- An **overview → drill-down** structure: a list of trackers, each a glass card with a **mini sparkline + headline stat**
  (count this period / latest value). Tap → a **per-tracker detail** with the full charts for that tracker's kind.
- **Chart by tracker kind:** numeric → value-vs-time **line**; count/quick-log → **bar trend**; _all kinds_ → the
  **hour-of-day × date scatter** (adherence). Scale/mood → line or distribution.
- **Empty / low-data states** are first-class — many trackers won't have enough points; design "Not enough data yet."

> This mirrors the Home **snapshot → "See all" → Trackers** pattern: an overview that scales to 10+ trackers, with the
> heavy charts behind a per-tracker drill-down rather than stacked on one giant scroll.

## Resolved decisions (brainstorm 2026-06-30)

| #   | Decision                                                             | Choice                                                                                                                                                                                                                | Why                                                                                                                                                                                                 |
| --- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Overview list + per-tracker drill-down, or all charts on one scroll? | **Overview + drill-down**                                                                                                                                                                                             | Scales to many trackers, matches Home→Trackers.                                                                                                                                                     |
| 2   | Timeframe control form — segmented chips vs dropdown?                | **Segmented** row (Week/Month/3M/Year/Custom), sticky; governs all charts.                                                                                                                                            | Glanceable, one tap; reuses `Stride/Chip`.                                                                                                                                                          |
| 3   | Which chart per tracker kind                                         | numeric→line, count→bar trend, all→scatter; scale→line.                                                                                                                                                               | Matches the data shape per kind.                                                                                                                                                                    |
| 4   | Cross-tracker overlay/correlation (BP vs mood)?                      | **Defer** — v1 single-tracker.                                                                                                                                                                                        | YAGNI; see Non-goals.                                                                                                                                                                               |
| 5   | Insights-tab active state in `Stride/Tab Bar`                        | Add an `Active=Home/Insights/Team/Settings` variant before reuse.                                                                                                                                                     | Component currently bakes Home active.                                                                                                                                                              |
| 6   | Headline stat(s) per overview card                                   | **Count + latest value** (e.g. "12 logs · last 128/82").                                                                                                                                                              | Works for every kind; most legible. Δ-vs-prior lives on the **detail stat strip**, not the overview card.                                                                                           |
| 7   | Sample data + per-tracker hue                                        | Bind to **[[sample-data]]** — active receiver **Eleanor** (retire "Margaret"); draw the overview roster from the canonical tracker list (overlap Home on BP/Medication/Pain); **Medication = violet, Weight = teal**. | Coherence review 2026-07-01: Insights named the receiver "Margaret" while Home said "Eleanor", showed Weight/Walk that Home/Trackers didn't, and swapped the Medication/Weight hues vs Add-Tracker. |
| 8   | Chart-kind selection vocabulary                                      | Derive line/bar/scatter from the contract `kind` + `Field.type` via the **[[sample-data]]** label mapping — not an ad-hoc numeric/count/scale/mood set.                                                               | The contract only has `event \| measurement \| scheduled`; the decision-3 vocabulary isn't contract-backed and diverges from the Trackers-screen labels.                                            |

### Scope of the first Figma pass

- **Two frames:** the **Insights overview** + **one** per-tracker **detail** drill-down, built for **Blood Pressure** (numeric → exercises the richest chart set: value-vs-time line + hour×date scatter + count bar). Remaining per-kind detail frames (count/scale/quick-log) follow in a later pass.
- **Placeholder sample data — realistic elder-care mix:** Blood Pressure (numeric line), Medications (count/adherence), Weight (numeric line), Pain (scale line), Walk (quick-log count bars). Designing ahead of the contract — see **Backend reality**.
- **Detail stat strip** carries 2–3 `Stride/Stat Card`s (e.g. Latest 128/82 · Avg 131/84 · 12 logs); this is where **Δ vs prior period** is shown.

## Design substrate — reuse, do not re-derive

**Figma:** file `qoiOteGuzktJPB6WKRbGHt` ("Stride Components"), page **App Flow** (`0:1`). Add a new **`Insights`**
section + a 393×852 frame; put any new chart components in the **`Components`** section (`84:4`). Existing sections:
Home `53:2`, Logging `84:2`, Trackers `84:3`, Components `84:4`.

**Palette — bind to variables, never hardcode.** The live cyan-on-navy "Aurora" palette lives in `aurora/*` +
`color/auth/*`. ⚠️ **`color/*` is STALE** (old blue Stride values, e.g. `color/accent`=#27a8f7) — do **not** bind to it.

| Token                               | Variable ID                                                                                                              | Hex                         |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------------------- |
| bg gradient top / bottom            | `17:14` / `17:15`                                                                                                        | #050b2e / #0a1640           |
| surface (cards)                     | `color/auth/surface` `17:16`                                                                                             | #0e1c4a                     |
| surface elevated                    | `17:17`                                                                                                                  | #16285c                     |
| border                              | `color/auth/border` `17:18`                                                                                              | ~#1a2d5c                    |
| **accent** (lines, active)          | `color/auth/accent` `17:19`                                                                                              | **#4dd6e6**                 |
| text primary / secondary / tertiary | `17:23` / `17:24` / `17:25`                                                                                              | #e8f0ff / #9db0d6 / #5e709c |
| text-on-accent (ink)                | `17:22`                                                                                                                  | #04121a                     |
| tracker hues                        | cyan `17:7` #4dd6e6 · teal `17:8` #3db8c4 · violet `17:9` #7c6ff0 · informational `10:30` #93c5fd · frost `17:6` #294272 |
| status                              | success `10:28` #3dd68c · warning `10:29` #fcd34d · alert `10:27` #ff4d6a                                                |

**Type:** **Space Grotesk** (display: titles, big stat numbers) + **Inter** (body/UI/axis labels). Ramp: 28 Medium → 22 → 16 → 14 → 13 → 12.
**Surfaces:** glass cards, radius 16, 1px border, soft shadow. Two **Aurora Glow** ellipses bleed from the top of every
frame (cyan→teal→violet linear @85%, 90px blur — clone from any existing app frame, e.g. Home glows). Background = vertical `#050b2e→#0a1640`.
**Signature:** _recency-as-luminance_ (cyan glow on fresh/active). Carry it into data viz: cyan data lines, a soft cyan→transparent area fill, scatter dots in tracker hue with glow on recent points. Spend boldness once; keep axes/grid quiet (border/tertiary).

## Components — what to reuse vs build

**Reuse (Stride/\*):** `Stride/Tab Bar` `89:52` (needs an Insights-active state — decision #5) · `Stride/Section Header` `90:92` · `Stride/Chip` `90:85` (timeframe segments / filters) · `Stride/Tracker Row` `92:107` or `Stride/Tracker Tile` `86:20` (overview entries) · `Stride/Status Badge` `90:78` · `Stride/Button` `24:6` · `Stride/Field` `34:9`.

**Build new (add to Components section):** `Stride/Timeframe Selector` (segmented) · `Stride/Stat Card` (label + big Space-Grotesk number + Δ) · `Stride/Chart/Line` (value-vs-time, area gradient) · `Stride/Chart/Scatter` (hour×date) · `Stride/Chart/Bar` (count trend) · `Stride/Sparkline` (overview mini) · chart axis/legend bits.

**Build-pattern reminders** (see [[caretosher-post-login-ia]]): components are role-named `Stride/*`; build a main component once + place instances; bind colors to the variable IDs above; override per-instance `Dot`/`Rail` fills + TEXT `.characters`. **Gotcha:** nodes parented to a Figma **Section use section-relative x/y** (offset ~88 for the title) — absolute coords push content outside the section box.

## Backend reality

No analytics endpoints (B3b/analytics not built). **Aggregate client-side** from `listEvents(trackerId, from:, to:)` over
the selected timeframe (same fan-out as [[activity-timeline]]): counts, value series, and hour-of-day are all derivable
from raw events. Long timeframes (Year) may need per-tracker pagination — note as deferred. The Figma pass uses
**placeholder data**; it's designing ahead of the contract, which is fine — flag it, don't pretend the data exists.

## Where it lives

### Built Figma nodes (file `qoiOteGuzktJPB6WKRbGHt`, page App Flow)

| Node                                                                                | ID                                |
| ----------------------------------------------------------------------------------- | --------------------------------- |
| `Insights` section                                                                  | `119:196`                         |
| Overview frame (`Insights · Overview`, 393×852)                                     | `119:197`                         |
| BP detail frame (`Insights · BP Detail`, 393×1130 scroll)                           | `119:375`                         |
| `Stride/Tab Bar` — variant set w/ `Active=Home\|Insights`                           | `112:196`                         |
| `Stride/Timeframe Selector`                                                         | `113:196`                         |
| `Stride/Insight Card` (TEXT props: Name/Count/Latest; hue via nested fill override) | `114:196`                         |
| `Stride/Stat Card` (TEXT props: Label/Value/Delta)                                  | `115:196`                         |
| `Stride/Chart/Line` · `Stride/Chart/Scatter` · `Stride/Chart/Bar`                   | `117:196` · `118:206` · `118:247` |

**Build notes for the SwiftUI pass:** cards + charts use **placeholder data**; the detail frame is a **scroll** artboard (taller than the 852 viewport, tab bar pinned to its bottom). Hue per tracker card = a nested-fill override on the Insight Card instance (`hue-dot`/`line`/`area`/`end-dot`), not a variant. The empty state ("Walk / Not enough data yet") is the same Insight Card with `statRow`+`spark` hidden and a muted `aurora/frost-500` dot — Theme.swift should model this as a card state, not a separate view.

| Concept                                           | Location                                                                                                                                         |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Design (lead)                                     | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Insights` section `119:196` (frames above); chart components → `Components` section `84:4` |
| iOS screen (placeholder today)                    | `ios/Caregiver/Insights/InsightsView.swift`                                                                                                      |
| Client-side aggregation pattern to copy           | `ios/Caregiver/Activity/ActivityModel.swift` (fan-out + merge)                                                                                   |
| Tokens (pending Theme.swift sync to cyan palette) | `ios/Caregiver/DesignSystem/Theme.swift` — still the **old blue**; adopting the Aurora palette is a known divergence (see [[design-system]])     |

## Non-goals (proposed)

- No cross-tracker correlation/overlay in v1 (single-tracker charts only).
- No export / share / report generation.
- No predictive or AI-driven analytics.
- No real backend analytics endpoint — client-side aggregation over `listEvents`.
- No editing data from Insights (read-only; edits happen via Event detail).
