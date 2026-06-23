# Design System Gallery

A standalone HTML gallery that documents and previews the Caregiver iOS app's
reusable components and design tokens. Spec: `ios/specs/design-gallery.md`.

## Viewing

Browsers block `fetch()` of local files over `file://`, so serve the folder:

```bash
cd ios/design-gallery
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Editing

- **Tokens** (colors, spacing, radii, type, gradients) live in `tokens.json` —
  the single source of truth. The `light` palette mirrors
  `ios/Caregiver/DesignSystem/Theme.swift`.
- **Add a palette:** add a named object under `palettes` in `tokens.json`; it
  appears in the palette dropdown automatically.
- **Add a component:** add a `.demo-card` block to `#components-grid` in
  `index.html` and style it in `components.css` using the `--color-*` /
  `--space-*` / `--radius-*` CSS variables so it re-themes with the palette.

## Scope

Phase 1 is the gallery only. A Swift `Theme` refactor and a `tokens.json`
parity test are deferred to Phase 2 (see the spec).
