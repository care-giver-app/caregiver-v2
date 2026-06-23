# Design System Gallery

- **Module:** ios
- **Status:** Current
- **Last updated:** 2026-06-23
- **Contract:** none (no backend interaction)
- **Related specs:** [[activity-timeline]], C1-UI navigation; design system in `ios/Caregiver/DesignSystem/`

> Living, conceptual spec for the iOS design-system gallery — a standalone HTML page that documents
> and previews the app's reusable components and theme. It does not touch the backend, so it
> references no OpenAPI contract.

## Purpose

A browser-based gallery that shows every reusable component and design token in one place, with a
live **palette toggle**, so the team can (a) document the earthy design language as it exists in
Swift and (b) explore new palettes — notably a not-yet-built **dark mode** — before implementing them.
It serves designers/developers, not end users; it ships nothing into the app bundle.

## Behavior

A single static HTML page (`ios/design-gallery/index.html`), viewed via a local static server. A
**sticky top bar** holds the global **palette control** (the only page-level toggle). The page body is
a **vertical list of equal-dimension slides** — one per row — each documenting a single token group or
component. Everything visual is driven by **CSS variables fed from the active palette in
`tokens.json`**, so switching palettes re-themes every slide live.

- **Palette control (sticky top):**
  - **Palette** dropdown — every named set in `tokens.json` (`light`, `dark`, any experiments).
    Switching rewrites the CSS variables; the whole page re-themes instantly.
  - **Light/Dark** — convenience shortcut that jumps to the `light` / `dark` palette, so dark mode is
    something you _design and see here_ before it exists in Swift.
- **Slides.** Every slide is the same fixed size and sits on its own row, with a clear **header** (the
  token group or component name) and, where applicable, an in-header **toggle**. Slide content scrolls
  within the fixed frame if it overflows, so dimensions stay uniform.
  - **Token slides** (no toggle): **Colors** (swatches, token name + hex), **Spacing** (visual bars),
    **Radius** (samples), **Type** (the ramp at real size/weight), **Gradient** (the `earth` gradient).
  - **Component slides** (one component, with a toggle): a segmented toggle in the header switches
    between that component's **unified states and variants** — exactly one shown at a time, centered
    over the `earthBackground`, with a small SwiftUI usage line beneath it that updates with the
    selection. A component with a single representation shows no toggle. Covered: `PrimaryButton`
    (default / pressed / disabled / loading), `SecondaryButton` (default / disabled), `GlassButton`
    (default / pressed), `GlassField` (plain / with-icon / secure), `glassCard`, `EmptyStateView`,
    `ErrorStateView`, `LoadingView`.
- **No build step, no framework.** Plain HTML/CSS/JS. `gallery.js` renders the slides data-drivenly
  from a component manifest plus the tokens; the component look (thin-material glass, top-down white
  highlight, hairline rim, soft shadow, earth gradient) is reproduced in `components.css` from the
  token CSS variables — a best-effort _visual_ match of the SwiftUI components, reviewed by eye.

### Source of truth & drift

`tokens.json` is the single shared source of truth for the token layer: named **palettes** (the color
set) plus the **scales** (spacing, radius, type) and **gradients**. The gallery reads it at load.

The intended end state (Approach A, deferred to Phase 2 below) is that `Theme.swift` is kept honest by
a **Swift parity test** that loads `tokens.json` from the test bundle and asserts every `palettes.light`
value equals the resolved `Theme.Colors.*` value, with scales matching too — failing in the existing
iOS CI job if Swift and JSON drift. The component _visuals_ are inherently hand-matched in CSS and not
covered by the test; only the token layer is.

### Scope phasing

- **Phase 1 (now):** the gallery + `tokens.json`. The `light` palette is lifted by hand from current
  `Theme.swift` values (accurate at authoring time); a first **`dark` palette is designed in the
  gallery**. No Swift changes. **Known gap:** until Phase 2, `tokens.json` is a hand-made snapshot with
  no automated drift guard against `Theme.swift`.
- **Phase 2 (deferred):** refactor `Theme.Colors` to a swappable `Palette` struct (one `active` palette
  constant; public API like `Theme.Colors.accent` unchanged, so no call sites change), and add the
  parity test. Closes the drift gap. Porting the gallery-designed `dark` palette into shipping Swift is
  a further, separate step gated on actually wanting dark mode.

### Viewing

Browsers block `fetch()` over `file://`, so the page is viewed through a one-line static server
(`python3 -m http.server` from `ios/design-gallery/`), documented in the folder README. Tokens stay
clean JSON (parseable by both JS and the future Swift test) rather than being inlined as a JS global.

## Key decisions

| Decision             | Choice                                                                                       | Why                                                                                                           |
| -------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Gallery purpose      | Both documentation _and_ design sandbox                                                      | One artifact to show what exists and to explore new palettes/dark mode before building                        |
| Theming end goal     | Devs re-theme in one place (one shipping theme), not user-runtime                            | Matches current `Theme.swift`; keeps the Swift change to a light token-layer refactor                         |
| Source of truth      | Shared `tokens.json` (palettes + scales)                                                     | Gallery and Swift read the same token data; palette toggle = swap a token set                                 |
| Drift mechanism      | Approach A — Swift **parity test**, not codegen                                              | Anti-drift guard with no new build pipeline; `Theme.swift` stays idiomatic; reuses existing iOS CI            |
| Tech                 | Plain HTML/CSS/JS, no framework, no build                                                    | Lowest friction; a design tool shouldn't carry a toolchain                                                    |
| Component fidelity   | Hand-matched CSS, eyeballed                                                                  | SwiftUI glass can't be generated into CSS; only tokens are truly shared                                       |
| Viewing              | Local static server (clean JSON) over double-click (inlined JS)                              | Keeps `tokens.json` parseable by the future Swift test; small one-line-server cost is acceptable              |
| Phasing              | Gallery first; `Theme` refactor + parity test deferred to Phase 2                            | User priority: get the visual gallery up now; accept a temporary manual-snapshot drift gap                    |
| Dark palette         | Designed in the gallery now, _not_ ported to Swift yet                                       | Lets dark mode be seen/iterated cheaply before committing Swift work                                          |
| Layout               | Equal-dimension slides, one per row (tokens + components), not a card grid                   | User feedback: cards were too big/inconsistent; a slide-per-thing reads cleanly and scales uniformly          |
| Component variations | One in-slide segmented toggle per component, unifying states + variants, one shown at a time | Keeps each slide self-contained and uniformly sized; "see each version" via a toggle, not side-by-side sprawl |

## Where it lives

| Concept                                                                                          | File                                          |
| ------------------------------------------------------------------------------------------------ | --------------------------------------------- |
| Page shell + sticky palette bar + empty slide-list host                                          | `ios/design-gallery/index.html`               |
| Gallery chrome: sticky bar + uniform slide frame + header/segmented-toggle                       | `ios/design-gallery/gallery.css`              |
| Component styles mimicking SwiftUI, driven by token vars                                         | `ios/design-gallery/components.css`           |
| Component manifest; render token + component slides; per-slide variation toggle + palette toggle | `ios/design-gallery/gallery.js`               |
| Source of truth: palettes + scales + gradients                                                   | `ios/design-gallery/tokens.json`              |
| How to view + add a palette/component                                                            | `ios/design-gallery/README.md`                |
| Existing tokens mirrored by `tokens.json` (`light`)                                              | `ios/Caregiver/DesignSystem/Theme.swift`      |
| Existing components reproduced in the gallery                                                    | `ios/Caregiver/DesignSystem/Components.swift` |
| Phase 2: `Palette` refactor + `active` palette                                                   | `ios/Caregiver/DesignSystem/Theme.swift`      |
| Phase 2: parity test (loads `tokens.json` from bundle)                                           | `ios/CaregiverTests/` (new test)              |
| Phase 2: wire `tokens.json` as test-target resource                                              | `ios/project.yml`                             |

## Non-goals

- Not shipped to end users; no runtime theme switching in the app (devs re-theme in one place).
- No build step, bundler, or JS framework for the gallery.
- No automated test of component _visual_ fidelity — only the token layer (via the Phase 2 parity test).
- No accessibility lens (Dynamic Type / contrast checks) in this round — deferred, slots in later.
- No C2-era components yet (breach badge using the reserved `alert` color, tracker-builder controls);
  the gallery is structured so they slot in as new slides (an entry in the component manifest).
- Phase 1 makes **no Swift changes** — the refactor and parity test are deferred to Phase 2.
