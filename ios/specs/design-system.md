# Stride design system (SwiftUI)

- **Module:** ios
- **Status:** Current — the app's reusable SwiftUI components + tokens. (Superseded the standalone browser **design-gallery** tool, removed 2026-07-01 now that Figma is the design source of truth.)
- **Last updated:** 2026-07-01
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
// .strideCard() — glass-card View modifier
StrideLoadingView · StrideEmptyState(message:) · StrideErrorState(message:retry:) · StrideDialog
```

`isLoading` only has a visual effect on `.primary`. `GlassButton` was removed; its call sites became
`.secondary`. Treat the Swift files (below) as the authoritative signatures — verify against them when
you next touch a component.

## Components

Reusable components live in `ios/Caregiver/DesignSystem/` and are consumed app-wide (Home, Auth,
Settings, Insights, Activity, Trackers, Dashboard, …):

| Component        | File                   | Notes                                                       |
| ---------------- | ---------------------- | ----------------------------------------------------------- |
| `StrideButton`   | `Components.swift`     | `style: .primary \| .secondary`, `isLoading` (primary only) |
| `StrideField`    | `Components.swift`     | `icon` (optional), `isSecure`                               |
| `.strideCard()`  | `Components.swift`     | glass card modifier                                         |
| state views      | `Components.swift`     | `StrideLoadingView`, `StrideEmptyState`, `StrideErrorState` |
| `StrideBadge`    | `StrideBadge.swift`    | status × style matrix — see below                           |
| `StrideTimeline` | `StrideTimeline.swift` | ordered `[TimelineNode]` — see below                        |
| `StrideDialog`   | `StrideDialog.swift`   | confirm/alert dialog                                        |

### StrideBadge

A small pill communicating status. Every field is optional at the call site, but provide at least one of
`icon`/`label`.

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

## Tokens & the Aurora migration

- **Canonical palette = Aurora** (cyan-on-navy) — defined in **Figma** and mirrored in the [[insights]]
  substrate table (accent `#4dd6e6`, bg `#050b2e → #0a1640`, tracker hues cyan/teal/violet, status
  success/warning/alert). [[sample-data]] owns the per-tracker hue map.
- **⚠️ `Theme.swift` still carries the old blue** (the "arctic" `accent #27a8f7` values, and the `alert`
  token name). **Adopting the Aurora palette in Swift is the known, tracked divergence** — every screen
  spec's "Tokens (pending Aurora sync)" row points here. Deferred design-system work, not per-screen.
- When the Swift sync happens: move `Theme.Colors` to the Aurora values, add the tracker-hue + status
  tokens, and (optionally) rename `alert → failure` for clarity. The old `tokens.json` parity-test idea
  is retired with the gallery — Figma is the source of truth now.

## Key decisions

| Decision               | Choice                                                                            | Why                                                                                          |
| ---------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Design source of truth | **Figma** (Aurora system) leads; this spec documents the Swift mirror             | 2026-07-01: the browser gallery + `tokens.json` were removed once Figma took over.           |
| Naming                 | **Stride** prefix, role-based names; `style:` param over separate types           | Decouples component identity from visual style; name survives aesthetic changes.             |
| Button consolidation   | Single `StrideButton(style:)` (replaced Primary/Secondary/GlassButton)            | Three types for one component was a smell.                                                   |
| Badge / Timeline       | `StrideBadge(status:style:)` + `StrideTimeline([TimelineNode])`, both implemented | Reusable primitives; Timeline node model adapts to varied consumers with graceful omission.  |
| Palette history        | earthy → single arctic `light` → **Aurora** (current)                             | Arctic was an interim; Aurora (Figma) is the real direction. `Theme.swift` sync is deferred. |

## Where it lives

| Concept                                                     | File                                              |
| ----------------------------------------------------------- | ------------------------------------------------- |
| `StrideButton`, `StrideField`, `.strideCard()`, state views | `ios/Caregiver/DesignSystem/Components.swift`     |
| `StrideBadge`                                               | `ios/Caregiver/DesignSystem/StrideBadge.swift`    |
| `StrideTimeline` + `TimelineNode`                           | `ios/Caregiver/DesignSystem/StrideTimeline.swift` |
| `StrideDialog`                                              | `ios/Caregiver/DesignSystem/StrideDialog.swift`   |
| Tokens (pending Aurora sync)                                | `ios/Caregiver/DesignSystem/Theme.swift`          |
| Design source of truth                                      | Figma `qoiOteGuzktJPB6WKRbGHt` (Aurora system)    |

## Non-goals

- No runtime theme switching in the app (single Aurora theme; devs re-theme in one place).
- No browser gallery / `tokens.json` / parity test — removed 2026-07-01 (Figma replaces it).
- No automated component-visual test.
