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
// .strideCard() — glass-card View modifier
StrideLoadingView · StrideEmptyState(message:) · StrideErrorState(message:retry:) · StrideDialog
```

`isLoading` only has a visual effect on `.primary`. `GlassButton` was removed; its call sites became
`.secondary`. Treat the Swift files (below) as the authoritative signatures — verify against them when
you next touch a component.

## Components

Reusable components live in `ios/Caregiver/DesignSystem/` and are consumed app-wide (Home, Auth,
Settings, Insights, Activity, Trackers, Dashboard, …):

| Component           | File                      | Notes                                                       |
| ------------------- | ------------------------- | ----------------------------------------------------------- |
| `StrideButton`      | `Components.swift`        | `style: .primary \| .secondary`, `isLoading` (primary only) |
| `StrideField`       | `Components.swift`        | `icon` (optional), `isSecure`                               |
| `.strideCard()`     | `Components.swift`        | glass card modifier                                         |
| state views         | `Components.swift`        | `StrideLoadingView`, `StrideEmptyState`, `StrideErrorState` |
| `StrideBadge`       | `StrideBadge.swift`       | status × style matrix — see below                           |
| `StrideTimeline`    | `StrideTimeline.swift`    | ordered `[TimelineNode]` — see below                        |
| `StrideDialog`      | `StrideDialog.swift`      | confirm/alert dialog                                        |
| `StrideTabBar`      | `StrideTabBar.swift`      | 4 tabs + raised ⊕ quick-log FAB — see below                 |
| `StrideTrackerTile` | `StrideTrackerTile.swift` | hue dot + name + last-logged; recency states — see below    |
| `StrideTrackerRow`  | `StrideTrackerRow.swift`  | full-width tracker list row; hue rail + recency — see below |

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

## Where it lives

| Concept                                                     | File                                                 |
| ----------------------------------------------------------- | ---------------------------------------------------- |
| `StrideButton`, `StrideField`, `.strideCard()`, state views | `ios/Caregiver/DesignSystem/Components.swift`        |
| `StrideBadge`                                               | `ios/Caregiver/DesignSystem/StrideBadge.swift`       |
| `StrideTimeline` + `TimelineNode`                           | `ios/Caregiver/DesignSystem/StrideTimeline.swift`    |
| `StrideDialog`                                              | `ios/Caregiver/DesignSystem/StrideDialog.swift`      |
| `StrideTabBar` + `StrideTab`                                | `ios/Caregiver/DesignSystem/StrideTabBar.swift`      |
| `StrideTrackerTile` + `StrideTrackerRecency`                | `ios/Caregiver/DesignSystem/StrideTrackerTile.swift` |
| `StrideTrackerRow`                                          | `ios/Caregiver/DesignSystem/StrideTrackerRow.swift`  |
| Tokens (core values = Aurora; hues/status pending)          | `ios/Caregiver/DesignSystem/Theme.swift`             |
| Design source of truth                                      | Figma `qoiOteGuzktJPB6WKRbGHt` (Aurora system)       |

## Non-goals

- No runtime theme switching in the app (single Aurora theme; devs re-theme in one place).
- No browser gallery / `tokens.json` / parity test — removed 2026-07-01 (Figma replaces it).
- No automated component-visual test.
