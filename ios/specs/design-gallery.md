# Design System Gallery (Stride)

- **Module:** ios
- **Status:** Current
- **Last updated:** 2026-06-24
- **Contract:** none (no backend interaction)
- **Related specs:** [[activity-timeline]], C1-UI navigation; design system in `ios/Caregiver/DesignSystem/`

> Living, conceptual spec for the iOS design-system gallery — a standalone HTML page that documents
> and previews the app's reusable components and design tokens. It does not touch the backend, so it
> references no OpenAPI contract.

## Purpose

A browser-based gallery that shows every reusable component and design token in one place, with a
live **palette toggle**, so the team can (a) document the **Stride** design language as it exists in
Swift and (b) explore new palettes — notably a not-yet-built **dark mode** — before implementing them.
It serves designers/developers, not end users; it ships nothing into the app bundle.

## Stride naming conventions

The design system is named **Stride**. All reusable components carry the `Stride` prefix. Component
names describe their **role**, not their visual style, so the name stays stable as the aesthetic
evolves.

Components with meaningfully different variants expose a `style` parameter rather than separate types:

```swift
enum StrideButtonStyle { case primary, secondary }
enum StrideBadgeStyle  { case tinted, filled, outlined }

StrideButton(title:style:isLoading:action:)   // collapses PrimaryButton, SecondaryButton
StrideField(placeholder:icon:isSecure:text:)
StrideBadge(status:style:icon:label:)         // gallery only for now; Swift deferred
// .strideCard() — View modifier
StrideLoadingView
StrideEmptyState(message:)
StrideErrorState(message:retry:)
```

The `isLoading` param on `StrideButton` only has a visual effect on `.primary`. There is no
third button style at present; the former `GlassButton` has been removed.

## Palettes

The gallery ships with a **single `light` palette** (the former `arctic` palette, promoted to be the
canonical theme). The earthy light and dark palettes have been removed. A `dark` palette will be
added later once the light theme is locked in.

### `light` palette

| Token           | Value     | Notes                                          |
| --------------- | --------- | ---------------------------------------------- |
| `accent`        | `#27a8f7` | Primary interactive color                      |
| `highlight`     | `#98d4ff` | Gradient start (StrideGradient)                |
| `tertiary`      | `#bac3e0` | Gradient end (StrideGradient)                  |
| `foreground`    | `#d1e1ff` | High-emphasis foreground                       |
| `textPrimary`   | `#d1e1ff` | Body text                                      |
| `textSecondary` | `#bac3e0` | Secondary text                                 |
| `textTertiary`  | `#6b7ea0` | Tertiary / placeholder text                    |
| `surface`       | `#071540` | Card / sheet surface                           |
| `background`    | `#010c30` | Page background                                |
| `border`        | `#1a2d5c` | Dividers and outlines                          |
| `success`       | `#3dd68c` | Positive status                                |
| `failure`       | `#ff4d6a` | Error / breach status _(renamed from `alert`)_ |
| `warning`       | `#FCD34D` | Caution status                                 |
| `informational` | `#93C5FD` | Neutral info status                            |
| `muted`         | `#5A6E9E` | De-emphasized status                           |

**Pending Swift sync:** `Theme.swift` still carries the old earthy values and `alert` token name.
Updating it to match the light palette and rename `alert` → `failure` is deferred to a future pass.

## Behavior

A single static HTML page (`ios/design-gallery/index.html`), viewed via a local static server. A
**sticky top bar** ("Stride") holds the global **palette control** (the only page-level toggle). The
page body is a **vertical list of equal-dimension slides** — one per row — each documenting a single
token group or component. Everything visual is driven by **CSS variables fed from the active palette
in `tokens.json`**, so switching palettes re-themes every slide live.

- **Palette control (sticky top):**
  - **Palette** dropdown — every named set in `tokens.json` (currently just `light`; `dark` slots in
    as a second entry when designed).
  - **Light/Dark** — convenience shortcut buttons, ready for when a second palette is added.
- **Slides.** Every slide is the same fixed size and sits on its own row, with a clear **header** (the
  token group or component name) and, where applicable, an in-header **toggle**. Slide content scrolls
  within the fixed frame if it overflows, so dimensions stay uniform.
  - **Token slides** (no toggle): **Colors** (swatches, token name + hex), **Spacing** (visual bars),
    **Radius** (samples), **Type** (the ramp at real size/weight), **Gradient** (the `stride` gradient).
  - **Component slides** (one component, with a toggle): a segmented toggle in the header switches
    between that component's **unified states and variants** — exactly one shown at a time, centered
    over the `strideBackground`, with a small SwiftUI usage line beneath it that updates with the
    selection. A component with a single representation shows no toggle. Covered: `StrideButton`
    (primary-default / primary-pressed / primary-disabled / primary-loading / secondary-default /
    secondary-disabled), `StrideField` (plain / with-icon / secure), `strideCard`,
    `StrideEmptyState`, `StrideErrorState`, `StrideLoadingView`, `Timeline`
    (read-only / tappable / minimal), and `StrideBadge` (tinted / filled / outlined).
- **No build step, no framework.** Plain HTML/CSS/JS. `gallery.js` renders the slides data-drivenly
  from a component manifest plus the tokens; the component look is reproduced in `components.css`
  from the token CSS variables — a best-effort _visual_ match of the SwiftUI components, reviewed
  by eye.

### StrideGradient

The `stride` gradient (formerly `earth`) runs from `highlight` to `tertiary` top-to-bottom. On the
light palette this renders as a blue-to-slate gradient. The CSS class is `.stride-bg`.

### StrideBadge

A small pill that communicates status. Every field is optional at the call site but at least one of
`icon` or `label` should be provided.

**Status variants** (one per semantic status token):

| Status           | Token                   | Light value |
| ---------------- | ----------------------- | ----------- |
| `.failure`       | `--color-failure`       | `#ff4d6a`   |
| `.warning`       | `--color-warning`       | `#FCD34D`   |
| `.informational` | `--color-informational` | `#93C5FD`   |
| `.success`       | `--color-success`       | `#3dd68c`   |
| `.muted`         | `--color-muted`         | `#5A6E9E`   |

**Style variants** (drive the color treatment):

| Style                 | Treatment                                                                 |
| --------------------- | ------------------------------------------------------------------------- |
| `.tinted` _(default)_ | 15% status color background, full status color text/icon                  |
| `.filled`             | 100% status color background, white text/icon                             |
| `.outlined`           | transparent background, 1.5px status color border, status color text/icon |

**Gallery slide:** three toggle variations — `Tinted`, `Filled`, `Outlined`. Each variation shows a
row of all five status badges (failure, warning, informational, success, muted) with icon + label,
so the full color × style matrix is visible at a glance. Unicode stand-ins for SF Symbols in the
gallery HTML (✕ ⚠ ℹ ✓ —).

**Swift API (deferred):**

```swift
StrideBadge(status: .failure, style: .tinted, icon: "xmark", label: "Failure")
StrideBadge(status: .warning, style: .filled, label: "Warning")  // icon optional
StrideBadge(status: .muted, style: .outlined, icon: "minus")     // label optional
```

### Timeline component

`Timeline` is a reusable list primitive: it takes an **ordered list of nodes** and renders, per node, a
fixed-width **gutter** (icon over short text), a **continuous vertical rail** with a colored **dot**
(trimmed above the first and below the last node so adjacent rows join into one line), and **content**
(title + description), plus an optional trailing chevron when the node is tappable. Earliest node at top.

**`TimelineNode` — every field optional:**

| Field         | Role                              | When omitted                                     |
| ------------- | --------------------------------- | ------------------------------------------------ |
| `icon`        | gutter SF Symbol                  | no icon (gutter column still reserves its width) |
| `iconTint`    | gutter icon color                 | defaults to `textSecondary`                      |
| `gutterText`  | text under the icon (e.g. a time) | no text                                          |
| `nodeColor`   | the rail dot                      | defaults to `accent` (the dot always draws)      |
| `title`       | content headline                  | line omitted                                     |
| `description` | content subline                   | line omitted                                     |
| `tap`         | row action                        | not tappable, no chevron                         |

The gutter and rail keep fixed-width columns regardless of which fields a node provides, so the rail
stays vertically aligned across rows. The activity tab is the intended consumer (sun/moon icon + tint
from `isDaytime`, formatted time as `gutterText`, tracker color/name/value summary, tap → event detail).

**Phasing:** the gallery documents `Timeline` and this node model now (a component slide — no Swift). The
reusable SwiftUI `Timeline` is **extracted from `ActivityRow` later, together with migrating the activity
tab to consume it**, so the API is validated against a real caller. This node model is the contract for
that extraction.

### Source of truth & drift

`tokens.json` is the single shared source of truth for the token layer: named **palettes** (the color
set) plus the **scales** (spacing, radius, type) and **gradients**. The gallery reads it at load.

The intended end state (Approach A, deferred to Phase 2 below) is that `Theme.swift` is kept honest by
a **Swift parity test** that loads `tokens.json` from the test bundle and asserts every `palettes.light`
value equals the resolved `Theme.Colors.*` value, with scales matching too — failing in the existing
iOS CI job if Swift and JSON drift. The component _visuals_ are inherently hand-matched in CSS and not
covered by the test; only the token layer is.

### Scope phasing

- **Phase 1 (now):** the gallery + `tokens.json`. One `light` palette (promoted from arctic). Status
  color tokens added (`failure`, `warning`, `informational`, `muted`). `StrideBadge` documented and
  styled in the gallery. **No Swift changes** — `Theme.swift` sync and `StrideBadge` SwiftUI
  implementation are deferred.
- **Phase 2 (deferred):** refactor `Theme.Colors` to a swappable `Palette` struct (one `active`
  palette constant; public API like `Theme.Colors.accent` unchanged, so no call sites change), rename
  `alert` → `failure` in Swift, add status tokens, and add the parity test. Porting the gallery's
  `dark` palette into shipping Swift is a further, separate step gated on actually wanting dark mode.

### Viewing

Browsers block `fetch()` over `file://`, so the page is viewed through a one-line static server
(`python3 -m http.server` from `ios/design-gallery/`), documented in the folder README. Tokens stay
clean JSON (parseable by both JS and the future Swift test) rather than being inlined as a JS global.

## Key decisions

| Decision              | Choice                                                                                          | Why                                                                                                             |
| --------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Gallery purpose       | Both documentation _and_ design sandbox                                                         | One artifact to show what exists and to explore new palettes/dark mode before building                          |
| Theming end goal      | Devs re-theme in one place (one shipping theme), not user-runtime                               | Matches current `Theme.swift`; keeps the Swift change to a light token-layer refactor                           |
| Source of truth       | Shared `tokens.json` (palettes + scales)                                                        | Gallery and Swift read the same token data; palette toggle = swap a token set                                   |
| Drift mechanism       | Approach A — Swift **parity test**, not codegen                                                 | Anti-drift guard with no new build pipeline; `Theme.swift` stays idiomatic; reuses existing iOS CI              |
| Tech                  | Plain HTML/CSS/JS, no framework, no build                                                       | Lowest friction; a design tool shouldn't carry a toolchain                                                      |
| Component fidelity    | Hand-matched CSS, eyeballed                                                                     | SwiftUI glass can't be generated into CSS; only tokens are truly shared                                         |
| Viewing               | Local static server (clean JSON) over double-click (inlined JS)                                 | Keeps `tokens.json` parseable by the future Swift test; small one-line-server cost is acceptable                |
| Phasing               | Gallery first; `Theme` refactor + parity test deferred to Phase 2                               | User priority: get the visual gallery up now; accept a temporary manual-snapshot drift gap                      |
| Dark palette          | Designed in the gallery later, _not_ in Swift yet                                               | Lets dark mode be seen/iterated cheaply before committing Swift work                                            |
| Layout                | Equal-dimension slides, one per row (tokens + components), not a card grid                      | User feedback: cards were too big/inconsistent; a slide-per-thing reads cleanly and scales uniformly            |
| Component variations  | One in-slide segmented toggle per component, unifying states + variants, one shown at a time    | Keeps each slide self-contained and uniformly sized; "see each version" via a toggle, not side-by-side sprawl   |
| Timeline              | Reusable `Timeline` taking an ordered `[TimelineNode]`; the activity tab becomes one consumer   | A timeline primitive instead of timeline-only inline rows — reusable wherever a node list is shown              |
| Timeline node fields  | Every field optional, graceful omission; gutter + rail keep fixed-width columns                 | Adapts to varied consumers without forcing data; fixed columns keep the rail aligned                            |
| Timeline sequencing   | Gallery slide now (no Swift); Swift extraction + activity-tab migration deferred, done together | Keeps the gallery-only PR clean; avoids an orphan component; validates the node API against a real caller       |
| Design system name    | **Stride** — all components prefixed `Stride`                                                   | Role-based names decouple component identity from visual style; name stays stable as aesthetic evolves          |
| Button consolidation  | Single `StrideButton(style:)` replacing `PrimaryButton`, `SecondaryButton`, `GlassButton`       | Three types for one component was a design smell; `GlassButton` removed, its call sites → `.secondary`          |
| Palette consolidation | Single `light` palette (arctic values); earthy light/dark removed                               | Arctic is the real design direction; earthy was a placeholder. Dark comes later once light is locked.           |
| `alert` → `failure`   | Renamed in `tokens.json`; Swift rename deferred                                                 | "failure" is clearer as a status semantic; "alert" was ambiguous. Swift rename tracks Phase 2.                  |
| Status color tokens   | `failure`, `warning`, `informational`, `success`, `muted` in `tokens.json`                      | Five semantic statuses cover the full range from error to de-emphasis; status-named tokens are self-documenting |
| Gradient rename       | `earth` → `stride` in `tokens.json`; `.earth-bg` → `.stride-bg` in CSS                          | "earth" reflected the old palette's aesthetic; "stride" is palette-neutral and matches the design system name   |
| Badge style param     | `StrideBadge(style:)` — `.tinted`, `.filled`, `.outlined`                                       | Mirrors `StrideButton(style:)` pattern; lets callers choose visual weight per context                           |
| Badge Swift timing    | Gallery only now; Swift `StrideBadge` deferred                                                  | Nail the visual design first; implement in Swift once the style is confirmed                                    |

## Where it lives

| Concept                                                                                          | File                                                     |
| ------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| Page shell + sticky "Stride" bar + empty slide-list host                                         | `ios/design-gallery/index.html`                          |
| Gallery chrome: sticky bar + uniform slide frame + header/segmented-toggle                       | `ios/design-gallery/gallery.css`                         |
| Component styles mimicking SwiftUI, driven by token vars                                         | `ios/design-gallery/components.css`                      |
| Component manifest; render token + component slides; per-slide variation toggle + palette toggle | `ios/design-gallery/gallery.js`                          |
| Source of truth: palettes + scales + gradients                                                   | `ios/design-gallery/tokens.json`                         |
| How to view + add a palette/component                                                            | `ios/design-gallery/README.md`                           |
| Stride component types (`StrideButton`, `StrideField`, `.strideCard()`, state views)             | `ios/Caregiver/DesignSystem/Components.swift`            |
| Existing tokens (pending sync with `tokens.json` light palette)                                  | `ios/Caregiver/DesignSystem/Theme.swift`                 |
| Timeline gallery slide (manifest entry + timeline CSS)                                           | `ios/design-gallery/gallery.js`, `components.css`        |
| Current inline gutter/rail/content (source for the later extraction)                             | `ios/Caregiver/Activity/ActivityRow.swift`               |
| Later: reusable `Timeline` extracted + activity tab migrated to it                               | `ios/Caregiver/DesignSystem/`, `ios/Caregiver/Activity/` |
| Phase 2: `Palette` refactor + `active` palette + `alert` → `failure` rename                      | `ios/Caregiver/DesignSystem/Theme.swift`                 |
| Phase 2: parity test (loads `tokens.json` from bundle)                                           | `ios/CaregiverTests/` (new test)                         |
| Phase 2: wire `tokens.json` as test-target resource                                              | `ios/project.yml`                                        |

## Non-goals

- Not shipped to end users; no runtime theme switching in the app (devs re-theme in one place).
- No build step, bundler, or JS framework for the gallery.
- No automated test of component _visual_ fidelity — only the token layer (via the Phase 2 parity test).
- No accessibility lens (Dynamic Type / contrast checks) in this round — deferred, slots in later.
- No C2-era components yet (tracker-builder controls); the gallery is structured so they slot in as new slides.
- Phase 1 makes **no Swift changes** — `Theme.swift` sync, `StrideBadge` SwiftUI, and `alert` → `failure` rename are all Phase 2.
- No Swift `Timeline` extraction or activity-tab migration in this round.
