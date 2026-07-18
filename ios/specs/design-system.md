# Stride design system (SwiftUI)

- **Module:** ios
- **Status:** Current — the app's reusable SwiftUI components + tokens. (Superseded the standalone browser **design-gallery** tool, removed 2026-07-01 now that Figma is the design source of truth.)
- **Last updated:** 2026-07-05
- **Contract:** none (no backend interaction).
- **Related specs:** every ios screen spec consumes these components; [[sample-data]] (canonical fixtures + tracker hue map), [[insights]] (Aurora palette substrate table), [[activity-timeline]] (the `StrideTimeline` consumer)

> Living reference for **Stride**, the app's SwiftUI design system in `ios/Caregiver/DesignSystem/`.
> **Design now happens in Figma** (file `qoiOteGuzktJPB6WKRbGHt`, the Aurora cyan-on-navy system) and
> leads the Swift build; this spec documents the **Swift side** — naming conventions, the reusable
> component set, and the token/`Theme.swift` state. The old browser gallery (`ios/design-gallery/`) and
> its `tokens.json`/parity-test approach were removed once Figma took over that role.

## Stride naming conventions

The design system is named **Stride**. All reusable components carry the `Stride` prefix. Names describe
their **role**, not their visual style, so the name stays stable as the aesthetic evolves (earthy →
arctic → Aurora). Components with meaningfully different looks expose a `style` parameter rather than
separate types:

```swift
enum StrideButtonStyle { case primary, secondary }
enum StrideBadgeStyle  { case tinted, filled, outlined }

StrideButton(title:style:isLoading:action:)   // collapses the former PrimaryButton/SecondaryButton/GlassButton
StrideField(placeholder:icon:isSecure:text:)
StrideBadge(status:style:icon:label:)
StrideTimeline(nodes:)                         // ordered [TimelineNode]
StrideTabBar(selection:onQuickLog:)            // selection: Binding<StrideTab>; ⊕ FAB action
StrideTrackerTile(name:subtitle:hue:recency:badge:) // recency: .fresh | .normal | .overdue; badge: StrideBadge?
StrideTrackerRow(name:subtitle:meta:hue:recency:badge:) // full-width Trackers-list row; same recency/badge model
StrideTimeframeSelector(selection:)            // selection: Binding<StrideTimeframe>; week | month | threeMonths | year | custom
StrideChip(label:isSelected:action:)           // self-sizing filter/choice pill; single-select lives in the consumer
StrideSectionHeader(title:actionLabel:action:) // tracked-uppercase section label + optional accent "See all ›"
StrideComingUpBanner(title:relativeLabel:action:) // Home look-ahead banner (Figma 64:2); amber relative label → pushes [[schedule]]
Toggle(…).toggleStyle(.stride)                 // StrideToggleStyle — Aurora capsule track on the system Toggle
StrideSelectTile(name:hue:isSelected:action:)  // picker-grid tile: hue dot + name + check ring; selection in consumer
StrideStatCard(label:value:delta:deltaColor:)  // Insights stat-strip card: tracked label + big stat + tinted delta
StrideInsightCard(name:hue:count:countCaption:latest:sparkline:) // Insights overview card w/ mini sparkline
StrideSparkline(values:hue:)                   // chrome-less filled area mini + endpoint dot (Path, not Swift Charts)
StrideLineChart(series:)                       // [StrideChartSeries] — value-vs-time lines + area under first series
StrideScatterChart(points:hue:)                // hour-of-day × date adherence scatter (midnight at top)
StrideBarChart(points:hue:)                    // count-per-bucket bar trend
StrideMemberRow(state:role:)                   // state: .active(name:initial:isYou:) | .pending(email:meta:onRevoke:)
StrideInviteCard(code:expiry:onShare:)         // glowing accent invite-code card; composes StrideButton
StrideReceiverRow(name:detail:initial:hue:isActive:) // switch-sheet row: hue monogram + ✓ when active
StrideSettingsRow(icon:label:trailing:)        // trailing: .none | .chevron | .check | .value(String) | .toggle(Binding)
StrideTemplateCard(style:)                     // style: .template(name:kind:icon:hue:) | .custom (dashed ⊕)
StrideBrand()                                  // fixed CareToSher logo plaque (auth screens' top anchor)
StrideCodeInput(code:length:)                  // 6-cell one-time-code entry; one hidden field drives it
// .strideCard() — glass-card View modifier
StrideLoadingView · StrideEmptyState(message:) · StrideErrorState(message:retry:) · StrideDialog
```

`isLoading` only has a visual effect on `.primary`. `GlassButton` was removed; its call sites became
`.secondary`. Treat the Swift files (below) as the authoritative signatures — verify against them when
you next touch a component.

## Components

Reusable components live in `ios/Caregiver/DesignSystem/` and are consumed app-wide (Home, Auth,
Settings, Insights, Activity, Trackers, Dashboard, …):

| Component                 | File                            | Notes                                                               |
| ------------------------- | ------------------------------- | ------------------------------------------------------------------- |
| `StrideButton`            | `StrideButton.swift`            | `style: .primary \| .secondary`, `isLoading` (primary only)         |
| `StrideField`             | `StrideField.swift`             | `icon` (optional), `isSecure`                                       |
| `.strideCard()`           | `StrideCard.swift`              | glass card modifier (pre-Aurora treatment — restyle pending)        |
| state views               | `StrideStateViews.swift`        | `StrideLoadingView`, `StrideEmptyState`, `StrideErrorState`         |
| `StrideBadge`             | `StrideBadge.swift`             | status × style matrix — see below                                   |
| `StrideTimeline`          | `StrideTimeline.swift`          | ordered `[TimelineNode]` — see below                                |
| `StrideDialog`            | `StrideDialog.swift`            | confirm/alert dialog                                                |
| `StrideTabBar`            | `StrideTabBar.swift`            | 4 tabs + raised ⊕ quick-log FAB — see below                         |
| `StrideTrackerTile`       | `StrideTrackerTile.swift`       | hue dot + name + last-logged; recency states — see below            |
| `StrideTrackerRow`        | `StrideTrackerRow.swift`        | full-width tracker list row; hue rail + recency — see below         |
| `StrideTimeframeSelector` | `StrideTimeframeSelector.swift` | segmented analytics-timeframe control — see below                   |
| `StrideChip`              | `StrideChip.swift`              | filter/choice pill, selected/default — see below                    |
| `StrideSectionHeader`     | `StrideSectionHeader.swift`     | uppercase section label + optional action — see below               |
| `StrideComingUpBanner`    | `StrideComingUpBanner.swift`    | Home "Coming up" look-ahead banner — see below                      |
| `StrideToggleStyle`       | `StrideToggle.swift`            | Aurora `ToggleStyle` (`.toggleStyle(.stride)`) — see below          |
| `StrideSelectTile`        | `StrideSelectTile.swift`        | picker-grid tile: hue dot + check ring — see below                  |
| `StrideStatCard`          | `StrideStatCard.swift`          | label + big stat + tinted delta — see below                         |
| `StrideInsightCard`       | `StrideInsightCard.swift`       | Insights overview card + `StrideSparkline` — see below              |
| chart components          | `StrideCharts.swift`            | `StrideLineChart`/`StrideScatterChart`/`StrideBarChart` — see below |
| `StrideMemberRow`         | `StrideMemberRow.swift`         | Team roster row, `.active`/`.pending` — see below                   |
| `StrideInviteCard`        | `StrideInviteCard.swift`        | glowing invite-code share card — see below                          |
| `StrideReceiverRow`       | `StrideReceiverRow.swift`       | receiver switch-sheet row — see below                               |
| `StrideSettingsRow`       | `StrideSettingsRow.swift`       | settings row, 5 trailing accessories — see below                    |
| `StrideTemplateCard`      | `StrideTemplateCard.swift`      | add-tracker template card + dashed custom — see below               |
| `StrideBrand`             | `StrideBrand.swift`             | CareToSher logo on a light ice-chip plaque — see below              |
| `StrideCodeInput`         | `StrideCodeInput.swift`         | segmented one-time-code entry — see below                           |

### StrideBadge

A small pill communicating status (Figma `Stride/Status Badge`, `90:78` — restyled to Aurora
2026-07-04: 11pt semibold, radius-8 rounded rect instead of a capsule). Every field is optional at the
call site, but provide at least one of `icon`/`label`. Figma only draws `.tinted` so far; `.filled`/
`.outlined` are kept as consistent treatments.

**Status variants** (one per semantic status token): `.failure` · `.warning` · `.informational` ·
`.success` · `.muted`.

**Style variants** (color treatment):

| Style                 | Treatment                                                                 |
| --------------------- | ------------------------------------------------------------------------- |
| `.tinted` _(default)_ | 15% status-color background, full status-color text/icon                  |
| `.filled`             | 100% status-color background, white text/icon                             |
| `.outlined`           | transparent background, 1.5px status-color border, status-color text/icon |

### StrideTimeline

`StrideTimeline` renders an **ordered `[TimelineNode]`**, earliest at top: per node a fixed-width
**gutter** (icon over short text), a **continuous vertical rail** with a colored **dot** (trimmed above
the first / below the last node so rows join into one line), and **content** (title + description), plus
an optional trailing chevron when tappable.

**`TimelineNode` — every field optional:**

| Field         | Role                              | When omitted                                |
| ------------- | --------------------------------- | ------------------------------------------- |
| `icon`        | gutter SF Symbol                  | no icon (gutter still reserves its width)   |
| `iconTint`    | gutter icon color                 | defaults to `textSecondary`                 |
| `gutterText`  | text under the icon (e.g. a time) | no text                                     |
| `nodeColor`   | the rail dot                      | defaults to `accent` (the dot always draws) |
| `title`       | content headline                  | line omitted                                |
| `description` | content subline                   | line omitted                                |
| `tap`         | row action                        | not tappable, no chevron                    |

The [[activity-timeline]] "Today" widget is the intended consumer (sun/moon icon + tint from
`isDaytime`, time as `gutterText`, tracker color/name/value, tap → event detail).

**Aurora restyle (2026-07-05, Figma `Stride/Timeline Node` `93:144`):** the node model is unchanged
but the drawing now matches the Aurora node — 52pt right-aligned 12pt-medium `textTertiary` time
gutter, an 11pt glowing dot **top-aligned** with the rail running _down_ from it (rail = 2pt
`border`), 14pt semibold title / 12pt `textSecondary` description, 18pt bottom padding between
nodes. The optional icon slot survives even though the Figma node doesn't draw one (the
activity-timeline consumer uses it).

### StrideTabBar

The post-login spine (Figma `Stride/Tab Bar`, set `112:196`): **Home · Insights · ⊕ · Team ·
Settings**. A **custom bar, not `TabView`** — the design deviates from the system bar (Aurora navy
surface, hairline top border, and a raised 58pt cyan quick-log FAB overhanging the bar by 14pt with
an accent glow), which a system `TabView` can't host.

- `StrideTab` — `home | insights | team | settings` (`CaseIterable`, tab-bar order). Owns each tab's
  title + SF Symbol name.
- `StrideTabBar(selection: Binding<StrideTab>, onQuickLog:)` — active tab = accent + semibold label;
  inactive = text-tertiary + medium. The ⊕ FAB fires `onQuickLog` ([[logging]] quick-log wizard).
- **Icons are SF Symbols** (`house` · `chart.bar` · `person.2` · `gearshape`; FAB = bold `plus`) —
  near-identical to the Figma `Stride/Icon/*` glyphs, chosen over bundled SVGs for Dynamic Type,
  weight control, and zero asset upkeep. Known visual drift: SF's `chart.bar` is filled where the
  Figma Insights glyph is three stroke lines; eventual cleanup is redrawing the Figma icons on the
  SF shapes so design and code re-converge.

### StrideTrackerTile

The Home snapshot's compact tracker cell (Figma `Stride/Tracker Tile`, set `86:20`): a 10pt **hue
dot** + tracker name + last-logged line on a surface card (radius 14, 1px border, padding 12). Sized
by its container — Home lays it in a 2-column grid.

**`StrideTrackerRecency`** carries the _recency-as-luminance_ signature: `.fresh` = the dot glows
(hue shadow, radius 3 @ 95%); `.normal` = plain hue dot; `.overdue` = the dot flips to `warning`
amber (status is a layer over the identity hue, never a hue itself — see [[sample-data]]).

**Status text is a `StrideBadge`**, not styled subtitle text (decided 2026-07-04, so status isn't
limited to "Due" — e.g. `.failure` "Missed"): the second line composes optional `subtitle` ("2h ago",
always text-tertiary) beside the optional `badge`, and is fixed at badge height so badged and plain
tiles grid-align. _Code leads Figma here_ — the Figma tile still draws "Due" as amber subtitle text;
fold the badge into the `Stride/Tracker Tile` variants on the next Figma pass.

### StrideTrackerRow

The Trackers view's full-width list row (Figma `Stride/Tracker Row`, set `92:107`; consumed by
[[trackers]]): a 4×40pt **hue rail** (radius 2) + name (16pt semibold) over a "Kind · value" subtitle
(13pt, text-tertiary), on a surface card (radius 16, 1px border, padding 14). Trailing **`meta`** text
("2h ago", 12pt medium) and a `chevron.right` are **pinned to the row's trailing edge** (decided
2026-07-05, Trevor) — the standard iOS list pattern, so recency scans down one consistent right edge.
_Code leads Figma here_: the Figma component hugs the trailing content to the text column (x-position
varies row to row in the Trackers frame — likely an auto-layout hug artifact); pin it right in the
`Stride/Tracker Row` variants on the next Figma pass. The chevron always draws: every row navigates
to tracker detail.

`StrideTrackerRecency` is shared with `StrideTrackerTile` and renders the same way on the rail:
`.fresh` glows (hue shadow @ 90%), `.normal` is the plain hue, `.overdue` flips the rail to `warning`
amber. Status text is the same optional **`badge:` slot** as the tile (Figma's overdue variant draws
the "Due" pill = `StrideBadge(.warning, "Due")` exactly, so it's composed, not redrawn); `meta` and
`badge` are independently optional — Figma's overdue variant passes a badge and no meta, but the API
doesn't couple them. Kept as a separate component from the tile (different shape, layout, and
trailing content); only the recency enum is shared.

### StrideTimeframeSelector

The Insights screen's timeframe control (Figma `Stride/Timeframe Selector`, `113:196`; consumed by
[[insights]], where one sticky selector governs every chart): five equal-width segments on a
`surface` track (height 40, radius 12, 1px `border`, 4pt inset, 2pt segment gap). The selected
segment is an `accent` pill (radius 9) with 13pt semibold `textOnAccent` ink; unselected segments
are 13pt medium `textSecondary`. Selection changes slide the pill via `matchedGeometryEffect`
(0.2s ease-in-out — no motion specced in Figma; a hard jump felt broken next to Aurora's glow).

- **`StrideTimeframe`** — `week | month | threeMonths | year | custom` (`CaseIterable`, display
  order). Owns each segment's label ("Week" · "Month" · "3M" · "Year" · "Custom"). What `.custom`
  triggers (a date-range sheet) belongs to the consumer; the selector only reports selection.
- **Custom, not `Picker(.segmented)`** — the Aurora track/pill/typography deviate from the system
  segmented control on every axis, and SwiftUI can't restyle it that far without global
  `UISegmentedControl.appearance()` hacks (same rationale as `StrideTabBar`).
- Concrete `StrideTimeframe` type per the role-naming convention, not a generic segmented control —
  generalize only when a second segmented consumer appears.

### StrideChip

A self-sizing filter/choice pill (Figma `Stride/Chip`, set `90:85`, variants `Type=Default` /
`Type=Selected`): a capsule that hugs its 13pt label (14pt horizontal / 8pt vertical padding).
Default = `surface` fill + 1px `border`, medium `textSecondary` label; selected = `accent` @ 16%
fill + 1px `accent` border, semibold `accent` label.

- **A dumb pill:** `StrideChip(label:isSelected:action:)`. The "exactly one selected" rule lives in
  the consumer row, not the chip — both Figma usages are single-select rows: the [[trackers]] filter
  row (`All · Needs attention · Archived`, frame `72:12`) and the [[team]] invite-sheet role picker
  (`Caregiver · Admin`, frame `150:643`).
- **Not the timeframe control** — the [[insights]] spec's decision #2 originally reused the chip for
  timeframes, but Figma grew the dedicated `Stride/Timeframe Selector` (`113:196`); the chip's role
  is now purely filter/choice.

### StrideSectionHeader

The section label row used across the post-login screens (Figma `Stride/Section Header`, `90:92`):
an uppercase 12pt semibold `textTertiary` title with 0.96pt tracking (the wide-tracked Aurora label
signature) on the left, and an optional accent action on the right — 12pt semibold `accent` label +
a small `chevron.right` (3pt gap), one tap target. Space-between layout, transparent background.

- The component **uppercases the title itself** (`title.uppercased()` + `.tracking`) — callers pass
  natural-case strings ("Today" → "TODAY") so the treatment stays a component concern.
- The action renders only when both `actionLabel` and `action` are provided; the title carries the
  `.isHeader` accessibility trait.

### StrideComingUpBanner

The Home "Coming up" banner (Figma `Stride` node `64:2`; consumed by [[home]], feeds [[schedule]]): a
tappable full-width pill on the surface card treatment (radius 14, `surface` fill + 1px `border`,
14pt padding) — an `exclamationmark.triangle.fill` glyph and the relative label both in `warning`
amber, the item title in `textPrimary` (14pt medium), a trailing `chevron.right`
(`textTertiary`). `StrideComingUpBanner(title:relativeLabel:action:)`; the whole pill is one
`Button` with a combined accessibility label. Amber is the app's single attention cue for the
look-ahead — everything on the [[schedule]] list stays calm (grey meta). Home renders it only when
there's an upcoming item; the tap pushes the [[schedule]] look-ahead.

### StrideToggleStyle

The Aurora switch treatment (Figma `Stride/Toggle`, set `156:572`; consumed by [[settings]]),
implemented as a **`ToggleStyle` on the system `Toggle`** rather than a custom view — call sites keep
the system semantics (label layout, tap target, VoiceOver on/off announcement) and only the drawing
is custom: a 46×28 capsule track (`accent` on / `surfaceHi` off) with a 22pt `textPrimary` snow
thumb sliding on a spring. Usage: `Toggle("Reminders", isOn: $flag).toggleStyle(.stride)`.

Added the **`surfaceHi` token** (`#16285c`, the live `color/auth/surface-hi` variable) for the
off-track — the first component to need the raised-surface value.

### Icons: `Stride/Icon` + `Stride/Tracker Icon` — no Swift component

Both Figma icon sets are glyph collections only, and per the standing SF-Symbols decision (tab bar,
2026-07-04) they map to system symbols at call sites rather than bundled assets or a wrapper type.
Tracker-kind glyphs (`Stride/Tracker Icon`, `171:960`): Heart → `heart` · Pill → `pills` · Scale →
`scalemass` · Pulse → `waveform.path.ecg` · Walk → `figure.walk` · Moon → `moon`. UI glyphs
(`Stride/Icon`, `157:600`) similarly (`person.2`, `plus`, `bell`, `shield`, `doc.text`,
`questionmark.circle`, `info.circle`, `rectangle.portrait.and.arrow.right`, `calendar`). Components
that show a tracker icon take an SF Symbol name (`icon: String`).

### StrideSelectTile

A selectable tracker tile for picker grids (Figma `Stride/Select Tile`, set `93:257`; the
[[logging]] quick-log wizard's "choose tracker" step): 10pt hue dot + 14pt semibold name + trailing
22pt check on a surface card (radius 14, 12/14pt padding). Unselected = 1.5pt `border` ring;
selected = `accent`-filled circle with an ink `checkmark` SF Symbol, and the card border thickens to
1.5pt `accent`. Like `StrideChip`, a dumb tile — selection state and single/multi rules live in the
consumer; carries the `.isSelected` accessibility trait.

### StrideStatCard

The Insights detail screen's stat-strip card (Figma `Stride/Stat Card`, `115:196`): tracked (0.5pt)
uppercase 11pt `textTertiary` label, 22pt stat value, optional 12pt tinted delta line on a surface
card (radius 12, 14/12pt padding). The component uppercases the label (same convention as
`StrideSectionHeader`). `deltaColor` defaults to `success`; pass `warning`/`alert`/`textTertiary`
for adverse or neutral deltas — direction arrows ("↑ ↓") travel inside the `delta` string, since
whether up is good depends on the metric. **Font note:** Figma sets the stat in Space Grotesk;
neither it nor Inter is bundled, so the system font (+ `monospacedDigit`) stands in — fold into the
pending bundled-font decision.

### StrideInsightCard + StrideSparkline

The Insights overview card, one per tracker (Figma `Stride/Insight Card`, `114:196`; consumed by
[[insights]] decision #6 — count + latest value): 8pt hue dot + 16pt semibold name; a 22pt count
with its 12pt `textTertiary` caption sharing the first text baseline; a 12pt `textSecondary`
"latest" line; and a 100×44 **`StrideSparkline`** pinned right. Dumb card — the consumer wraps it
in a `Button` for the drill-down tap. Surface card, radius 14, 16/14pt padding.

`StrideSparkline(values:hue:)` is a chrome-less filled area mini (85% hue fill + endpoint dot),
drawn with `Path` rather than Swift Charts — no axes, cheap in scrolling lists, normalizes raw
values to its bounds. The full-size Insights charts are separate Swift-Charts components.

### Charts: StrideLineChart · StrideScatterChart · StrideBarChart

The full-size [[insights]] charts (Figma `Stride/Chart/Line` `117:196`, `Scatter` `118:206`, `Bar`
`118:247`), built on **Swift Charts** (never hand-drawn rectangles) over a shared model —
`StrideChartPoint(date:value:)` and, for multi-line, `StrideChartSeries(name:hue:points:)`. All
three share the Aurora chart chrome (private `StrideChartCard` modifier): surface card radius 14,
16pt padding, **horizontal-only** `border` gridlines, 10pt `textTertiary` labels both axes, 150pt
plot height.

- **Line** — one `LineMark` series per entry (2pt stroke, series hue), gradient area fill under the
  _first_ series (22% → 2% hue), a glowing 9pt dot on each series' latest point, and a custom dot
  legend (Charts' own legend is hidden — it can't match the treatment).
- **Scatter** — the adherence view: `value` = hour-of-day (0–24), y-scale **inverted** (midnight at
  top, like the Figma plot) with fixed `12a · 6a · 12p · 6p` marks; the latest date's points draw
  9pt with glow, the rest 7pt @ 80%.
- **Bar** — counts per week bucket, 4pt top corner radius. _Known drift:_ Figma glows the latest
  bar; `BarMark` can't take a per-mark shadow, so the latest bar draws at full hue and earlier bars
  at 85% instead.

### StrideMemberRow

The [[team]] roster row (Figma `Stride/Member Row`, set `144:427`). The two states are structurally
different, so they're an enum with associated values: **`.active(name:initial:isYou:)`** — 36pt
`surfaceHi` monogram avatar (1.5pt `accent` ring + accent-tinted "You" tag when `isYou`), 16pt
semibold name, trailing `accent`-text role badge on a `surfaceHi` capsule; **`.pending(email:meta:
onRevoke:)`** — envelope avatar, 15pt `textSecondary` email over 12pt `textTertiary` meta
("Invited · expires 7d"), muted role badge + ✕ revoke button (the row's only action).

### StrideInviteCard

The token-first invite share card (Figma `Stride/Invite Card`, `145:421`; [[team]] invite sheet):
tracked "INVITE CODE" label, 26pt code (2pt tracking) beside a `surface` expiry pill, and a
composed **`StrideButton`** primary "Share link". The one glowing card in the system — raised
`surfaceHi` fill, 1px `accent` border, 12pt cyan shadow @ 20% — because it's the artifact being
handed to someone.

### StrideReceiverRow

The receiver switch/add sheet row (Figma `Stride/Receiver Row`, set `166:768`; [[receivers]]):
40pt monogram avatar filled with the receiver's hue @ 15% and the initial in full hue, 16pt
semibold name over a 13pt `textSecondary` detail line ("72 years"), and an `accent` checkmark when
active. Dumb row — the sheet wraps it in a `Button`.

### StrideSettingsRow

The [[settings]] list row (Figma `Stride/Settings Row`, set `158:620`): 20pt SF Symbol
(`textSecondary`) + 15pt medium label + a `Trailing` accessory enum — `.none` · `.chevron` ·
`.check` (accent) · `.value(String)` (14pt `textTertiary`) · `.toggle(Binding<Bool>)` (binds
through `StrideToggleStyle`). Only the toggle is self-interactive; navigation taps wrap the row in
a `Button`.

### StrideTemplateCard

The [[add-tracker]] wizard's choose-template card (Figma `Stride/Template Card`, set `174:948`),
2-column grid, fixed 146pt height so rows align: **`.template(name:kind:icon:hue:)`** — 44pt
hue @ 18% icon square (radius 12) with the hue glyph, 15pt semibold name, kind badge on a
`surfaceHi` capsule; **`.custom`** — dashed 1.5pt `border` card with centered accent ⊕ "Custom".
Templates come from `GET /tracker-templates`; the icon is an SF Symbol name per the icon mapping
above.

### StrideBrand

The CareToSher brand plaque (Figma `Stride/Brand`, `46:34`; the top anchor of all five auth
screens): the existing `AppLogo` asset (dark navy mark, **220×140 frame, no padding** — Trevor
tuned this by eye 2026-07-05 from Figma's 200×82 + 16/12 padding; the mark draws ~220×90 inside
the frame, so the letterbox _is_ the vertical breathing room. _Code leads Figma_, resize
`Stride/Brand` next Figma pass) on a near-white "ice chip" slab —
`#f1f6ff` @ 96%, radius 20, 1px white @ 70% hairline — with a cyan glow + deep drop shadow so it
reads as lit ice on the navy background. The plaque colors are deliberate one-offs (a light chip on
a dark system; they match no surface token). No parameters. User-facing brand = **CareToSher**,
never "Stride".

### StrideCodeInput

The segmented one-time-code entry (Figma `Stride/Code Input` `48:39`, cells `Stride/Code Digit`
`47:39`; the confirm-code auth screen): `length` (default 6) 50×60 cells — radius 14, `surface`
fill, 1px `textSecondary` @ 40% frost hairline, 22pt semibold digit — at a 9pt gap. The focus ring
(1.5pt `accent` + cyan glow, Figma's `Focused` boolean) sits on the next empty cell.

**Interactive, unlike most Stride components:** one hidden `TextField` (`.numberPad`,
`.textContentType(.oneTimeCode)`) drives the whole row, so the system keyboard and SMS/email code
autofill work while the cells stay purely visual — per-cell fields fight iOS autofill. The consumer
owns `code: Binding<String>`; every edit passes through `StrideCodeInput.sanitized(_:length:)`
(digits only, capped at `length` — unit-tested), so paste/autofill with separators lands clean.

### StrideButton + StrideField — Aurora reconcile (2026-07-05)

The two oldest components (C1-foundation era, pre-Aurora) restyled to their Figma sets
(`Stride/Button` `24:6`, `Stride/Field` `34:9`) with **APIs unchanged**, so every existing call
site (auth, onboarding, Home, tracker detail) picks the restyle up for free:

- **Button** — 54pt min height, radius 16. Primary: `accent` fill + top sheen, **`textOnAccent`
  ink label** (was white — the headline fix), cyan glow shadow; the `isLoading` spinner is ink
  too. Secondary: 1.5pt `textSecondary` @ 55% border, `textPrimary` label.
- **Field** — 56pt min height, radius 16, `surface` fill, 1px `textSecondary` @ 40% frost hairline
  (the auth-surface treatment shared with the code digit), 20pt `textSecondary` icon slot,
  `textTertiary` placeholder (was white-alpha).
- The pre-Aurora `Theme.Radius.control` (11pt) died with the restyle — both components now carry
  their radius in local `Metrics` like every other Aurora component; removed from `Theme.swift`.

**Auth icons** (Figma `Stride/Icon/Person·Lock·Envelope·Hash`, `33:9`–`33:15`) follow the standing
SF-Symbols decision: `person` · `lock` · `envelope` · `number`, passed as `StrideField`'s `icon:`.

### `.strideAuroraBackground()`

The Aurora screen substrate (the auth frames' background, `StrideAuroraBackground.swift`): a
vertical `background → #0a1640` night gradient with two soft glows bleeding in from the top —
`accent` @ 22% top-leading (560×300, blur 70) and `trackerViolet` @ 16% upper-trailing (420×220,
blur 60). Figma draws the glows as pre-blurred ellipse PNGs; the modifier draws blurred `Ellipse`s
instead so no raster asset ships (an eye-tuned approximation). Used by the [[auth]] screens.
**Post-login screens** (from the [[shell]] assembly pass, 2026-07-05) use the same night gradient
**without the glow ellipses** — the glows are an auth-screen signature; app frames sit on the plain
night substrate. This retires the old pre-Aurora `.strideBackground()` gradient.

## Tokens & the Aurora migration

- **Canonical palette = Aurora** (cyan-on-navy) — defined in **Figma** and mirrored in the [[insights]]
  substrate table (accent `#4dd6e6`, bg `#050b2e → #0a1640`, tracker hues cyan/teal/violet, status
  success/warning/alert). [[sample-data]] owns the per-tracker hue map.
- **Core `Theme.Colors` values are synced to Aurora** (2026-07-04, with the first Aurora component,
  `StrideTabBar`): `accent/textPrimary/textSecondary/textTertiary/surface/background/border` now hold
  the Aurora values, plus new `textOnAccent` (`#04121a`, ink on cyan fills). `border` = **`#294272`**
  per the live `color/auth/border` variable (the [[insights]] table's `~#1a2d5c` was stale).
- **Tracker hues are in** (2026-07-04, with `StrideTrackerTile`): `trackerCyan #4dd6e6` ·
  `trackerTeal #3db8c4` · `trackerViolet #7c6ff0`; info-blue trackers reuse `informational`.
- **Still pending from the sync:** status-token review, the `alert → failure` rename,
  and the non-token treatments — `highlight`/`Gradients.stride` (the old overlay gradient; Aurora
  screens use a plain `#050b2e → #0a1640` vertical + glow ellipses) and the `.strideCard()` fill
  (`tertiary`-based; Aurora cards are `surface` + 1px `border`). Migrate these as components need them.
  The old `tokens.json` parity-test idea is retired with the gallery — Figma is the source of truth now.

## Key decisions

| Decision               | Choice                                                                             | Why                                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Design source of truth | **Figma** (Aurora system) leads; this spec documents the Swift mirror              | 2026-07-01: the browser gallery + `tokens.json` were removed once Figma took over.            |
| Naming                 | **Stride** prefix, role-based names; `style:` param over separate types            | Decouples component identity from visual style; name survives aesthetic changes.              |
| Button consolidation   | Single `StrideButton(style:)` (replaced Primary/Secondary/GlassButton)             | Three types for one component was a smell.                                                    |
| Badge / Timeline       | `StrideBadge(status:style:)` + `StrideTimeline([TimelineNode])`, both implemented  | Reusable primitives; Timeline node model adapts to varied consumers with graceful omission.   |
| Palette history        | earthy → single arctic `light` → **Aurora** (current)                              | Arctic was an interim; Aurora (Figma) is the real direction. `Theme.swift` sync is deferred.  |
| Aurora token sync      | Core `Theme.Colors` values flipped to Aurora with the first Aurora component       | 2026-07-04: components bind to tokens; shipping `StrideTabBar` on old-blue would ship wrong.  |
| Tab bar                | Custom `StrideTabBar`, not system `TabView`                                        | The raised glowing ⊕ FAB + navy surface deviate from the system bar; `TabView` can't host it. |
| Tab bar icons          | SF Symbols (`house`, `chart.bar`, `person.2`, `gearshape`, `plus`), not SVG assets | 2026-07-04 (Trevor): near-identical glyphs + Dynamic Type/weight for free, no assets to keep. |
| Code input             | Interactive (one hidden one-time-code field), not a dumb cell row                  | 2026-07-05: autofill + number pad need a real field; per-cell fields fight iOS autofill.      |
| Button/Field reconcile | Restyled in place to the Figma sets; APIs unchanged                                | 2026-07-05: every pre-Aurora call site inherits the restyle with zero call-site churn.        |

## Where it lives

| Concept                                            | File                                                       |
| -------------------------------------------------- | ---------------------------------------------------------- |
| `StrideButton`                                     | `ios/Caregiver/DesignSystem/StrideButton.swift`            |
| `StrideField`                                      | `ios/Caregiver/DesignSystem/StrideField.swift`             |
| `.strideCard()`                                    | `ios/Caregiver/DesignSystem/StrideCard.swift`              |
| state views                                        | `ios/Caregiver/DesignSystem/StrideStateViews.swift`        |
| `StrideBadge`                                      | `ios/Caregiver/DesignSystem/StrideBadge.swift`             |
| `StrideTimeline` + `TimelineNode`                  | `ios/Caregiver/DesignSystem/StrideTimeline.swift`          |
| `StrideDialog`                                     | `ios/Caregiver/DesignSystem/StrideDialog.swift`            |
| `StrideTabBar` + `StrideTab`                       | `ios/Caregiver/DesignSystem/StrideTabBar.swift`            |
| `StrideTrackerTile` + `StrideTrackerRecency`       | `ios/Caregiver/DesignSystem/StrideTrackerTile.swift`       |
| `StrideTrackerRow`                                 | `ios/Caregiver/DesignSystem/StrideTrackerRow.swift`        |
| `StrideTimeframeSelector` + `StrideTimeframe`      | `ios/Caregiver/DesignSystem/StrideTimeframeSelector.swift` |
| `StrideChip`                                       | `ios/Caregiver/DesignSystem/StrideChip.swift`              |
| `StrideSectionHeader`                              | `ios/Caregiver/DesignSystem/StrideSectionHeader.swift`     |
| `StrideComingUpBanner`                             | `ios/Caregiver/DesignSystem/StrideComingUpBanner.swift`    |
| `StrideToggleStyle`                                | `ios/Caregiver/DesignSystem/StrideToggle.swift`            |
| `StrideSelectTile`                                 | `ios/Caregiver/DesignSystem/StrideSelectTile.swift`        |
| `StrideStatCard`                                   | `ios/Caregiver/DesignSystem/StrideStatCard.swift`          |
| `StrideInsightCard` + `StrideSparkline`            | `ios/Caregiver/DesignSystem/StrideInsightCard.swift`       |
| charts + `StrideChartPoint`/`StrideChartSeries`    | `ios/Caregiver/DesignSystem/StrideCharts.swift`            |
| `StrideMemberRow`                                  | `ios/Caregiver/DesignSystem/StrideMemberRow.swift`         |
| `StrideInviteCard`                                 | `ios/Caregiver/DesignSystem/StrideInviteCard.swift`        |
| `StrideReceiverRow`                                | `ios/Caregiver/DesignSystem/StrideReceiverRow.swift`       |
| `StrideSettingsRow`                                | `ios/Caregiver/DesignSystem/StrideSettingsRow.swift`       |
| `StrideTemplateCard`                               | `ios/Caregiver/DesignSystem/StrideTemplateCard.swift`      |
| `StrideBrand`                                      | `ios/Caregiver/DesignSystem/StrideBrand.swift`             |
| `StrideCodeInput`                                  | `ios/Caregiver/DesignSystem/StrideCodeInput.swift`         |
| Tokens (core values = Aurora; hues/status pending) | `ios/Caregiver/DesignSystem/Theme.swift`                   |
| Design source of truth                             | Figma `qoiOteGuzktJPB6WKRbGHt` (Aurora system)             |

## Non-goals

- No runtime theme switching in the app (single Aurora theme; devs re-theme in one place).
- No browser gallery / `tokens.json` / parity test — removed 2026-07-01 (Figma replaces it).
- No automated component-visual test.
