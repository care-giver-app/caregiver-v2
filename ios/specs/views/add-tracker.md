# Add a tracker

- **Module:** ios
- **Status:** Figma design pass **done** (2-step wizard: choose-template + configure; Template Card + Tracker Icon components) — next is the SwiftUI build.
- **Last updated:** 2026-07-01
- **Contract:** `GET /tracker-templates` → `TrackerTemplate[]` (seeded catalog: `{template_id, name, kind, fields, icon, color}`); `createTracker(receiverId, TrackerWrite{name, kind, fields, icon?, color?})` **admin-only** (`shared/openapi/openapi.yaml`). `TrackerKind = event | measurement | scheduled`. `Field = {key, label, type(number|text|boolean|enum|datetime), unit?, required?, options?[], threshold?{min,max}}`.
- **Related specs:** [[receivers]] (a tracker belongs to the active receiver), [[insights]] (renders tracker data), [[design-system]] (Stride design system), [[caretosher-post-login-ia]]

> **Read this before building.** It captures why the flow is template-first, the contract that shapes it, resolved
> decisions, and the built Figma node IDs. The **entry point already exists** — the Trackers browse screen's **"New"
> button** (`72:5`). Design happened in the CareToSher Figma file, then leads the SwiftUI build.

## Purpose

Admins add trackers to the **active receiver**. A tracker has a `kind`, a custom `fields[]` schema (types, units,
required, options, min/max **threshold**), and an `icon`/`color`. Hand-authoring that schema is too much for the common
case, so the flow leans on the **seeded `TrackerTemplate` catalog**: pick a template → tweak → create.

## Backend reality (shapes the design)

- **`GET /tracker-templates` is real** — the seeded catalog is the backbone of the flow (Blood Pressure, Weight,
  Medication, Pain, Walk, Sleep, …). Each template carries `name/kind/fields/icon/color`, so choosing one pre-fills
  everything; the user only tweaks.
- **`createTracker` is admin-only** and lives under the receiver (`/receivers/{receiverId}/trackers`) — the new tracker
  belongs to the currently-active [[receivers|receiver]].
- **Three kinds only:** `event` (things that happen — Walk, Meals), `measurement` (numeric series — BP, Weight, Pain),
  `scheduled` (Medication). The kind comes from the template; the wizard shows it as a badge.
- `icon` + `color` are real optional fields → the Configure step exposes a **color picker** and the template's glyph.
- `threshold{min,max}` on a `Field` drives Breach detection → the Configure step exposes an **ALERT** min/max card.

## Resolved decisions (brainstorm 2026-07-01)

| #   | Decision                                    | Choice                                                                                                                                                                                | Why                                                                                                                                                                                    |
| --- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Flow model                                  | **Template-first**, 2-step **full-screen wizard** (choose → configure)                                                                                                                | The seeded catalog exists precisely so the common case isn't hand-building a field schema. Full-screen (like the quick-log wizard) because the configure step is too rich for a sheet. |
| 2   | Entry point                                 | The existing **Trackers "New" button** `72:5`                                                                                                                                         | Already designed; the flow behind it didn't exist.                                                                                                                                     |
| 3   | Step 1 content                              | Template gallery (2-col cards, hue icon + kind badge) + a **Custom** card                                                                                                             | Fast recognition; Custom is the escape hatch.                                                                                                                                          |
| 4   | Step 2 content                              | Pre-filled: **name**, **color**, **fields** (read-only rows), **threshold** (min/max card), Create                                                                                    | Everything a `TrackerWrite` needs; editing thresholds matters for Breach alerts.                                                                                                       |
| 5   | Custom path                                 | Card now; **blank-config screen deferred**                                                                                                                                            | YAGNI for the first pass; the template path is the 90% case.                                                                                                                           |
| 6   | Which template to build Configure around    | **Blood Pressure** (measurement)                                                                                                                                                      | Richest — exercises two fields + unit + min/max threshold.                                                                                                                             |
| 7   | Per-template hue                            | Use the canonical map in **[[sample-data]]** (BP cyan · Weight teal · Medication violet · Pain info-blue · Walk teal · Sleep violet).                                                 | Coherence review 2026-07-01: Insights drew Medication teal / Weight violet — the inverse of this pass. One hue per tracker, everywhere.                                                |
| 8   | Threshold is **per-field**, not per-tracker | The ALERT card must bind to a specific `Field.threshold`; a 2-field tracker (Systolic + Diastolic) needs a threshold row **per field**, not one shared MIN/MAX.                       | Coherence review 2026-07-01: the Configure frame (`177:982`) shows a single MIN 90 / MAX 140 card with no field label, but the contract's `threshold` lives on each `Field`.           |
| 9   | Color-swatch palette                        | Offer only the **tracker-hue** palette (cyan/teal/violet/info-blue); **exclude status colors** (amber `#fcd34d` warning, red `#ff4d6a` alert).                                        | Coherence review 2026-07-01: the picker offered amber+red, which collide with the recency-as-luminance status semantics (amber = "Due"/overdue, red = breach).                         |
| 10  | Kind badge vs Trackers-list label           | Add-Tracker shows the raw contract `kind` (Event/Measurement/Scheduled); the [[trackers]] list shows the derived friendly label. Reconcile via the **[[sample-data]]** label mapping. | Coherence review 2026-07-01: the two screens present "kind" with different vocabularies; only `kind` is contract-backed.                                                               |

### Scope of the first Figma pass

- **Two frames:** `Choose template` (gallery) + `Configure` (pre-filled from Blood Pressure, a **scroll artboard**).
- Wizard is **full-screen, no tab bar** (matches the quick-log wizard), with a back control + 2-dot step indicator.
- **Sample templates:** Blood Pressure (cyan) · Weight (teal) · Medication (violet) · Pain level (info blue) · Walk
  (cyan) · Sleep (violet) · Custom.

## Design substrate — reuse, do not re-derive

Same Aurora substrate as [[insights]] — **read that spec's substrate table**. Both frames were built by **cloning a
prior frame** (the Insights overview) for the bg gradient + `Aurora Glow` ellipses, then **removing the tab bar** and
rebuilding the content (the wizard is modal/full-screen).

## Components — reuse vs build

**Reuse:** `Stride/Field` (name), `Stride/Button` (Create tracker), section-header + back-nav patterns.

**Build new (added to Components section `84:4`):**

- `Stride/Template Card` — variant set `Type = Template | Custom`. Template = hue icon square (`iconSquare` + swappable
  `glyph`) + `Name` + `Kind` badge; TEXT props `{Name, Kind}` + **Icon (INSTANCE_SWAP)**. Custom = dashed card + plus +
  "Custom". Per-template hue = per-instance override of `iconSquare` fill + `glyph` vector strokes.
- `Stride/Tracker Icon` — variant set `Name = Heart | Pill | Scale | Pulse | Walk | Moon` (22px glyphs), the swap target
  for the Template Card `Icon` property.
- **Inline (one-offs, low reuse):** the 2-dot step indicator, the color-swatch picker, the FIELDS rows, and the ALERT
  threshold min/max card.

### Build gotchas (for the SwiftUI build & future Figma edits)

- **Per-instance hue washes must be raw solids at reduced opacity, not variable-bound paints** — see the same gotcha in
  [[receivers]]: a bound paint's opacity resets to 1 on instance derivation. Template-card `iconSquare` washes are raw
  `hue @ 0.18`; glyph strokes are raw full-hue.
- The wizard frames are **cloned overview frames with the tab bar removed**; Configure is a **scroll artboard** (resize
  to content height — no tab bar, so no bottom pin).
- Field rows + threshold card are **inline**, not components — if a Custom/edit flow lands later, promote them to
  `Stride/Field Row` + `Stride/Threshold Card`.

## Where it lives

### Built Figma nodes (file `qoiOteGuzktJPB6WKRbGHt`, page App Flow)

| Node                                                                                                                                         | ID        |
| -------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `Add Tracker` section                                                                                                                        | `176:938` |
| Choose-template frame (`Add Tracker · Choose template`, 393×852)                                                                             | `176:939` |
| Configure frame (`Add Tracker · Configure`, 393×862 scroll)                                                                                  | `177:982` |
| `Stride/Template Card` — variant set (`Type=Template` `174:937` · `Type=Custom` `174:944`)                                                   | `174:948` |
| `Stride/Tracker Icon` — variant set (Heart `171:939` · Pill `171:943` · Scale `171:948` · Pulse `171:951` · Walk `171:956` · Moon `171:959`) | `171:960` |

| Concept                                           | Location                                                                                                                       |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Design (lead)                                     | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Add Tracker` section `176:938`; components → `Components` section `84:4` |
| Entry point (exists)                              | Trackers frame `71:2` → Nav → `New` button `72:5`                                                                              |
| iOS screen (to build)                             | `ios/Caregiver/Trackers/…` (a create-tracker wizard)                                                                           |
| Tokens (pending Theme.swift sync to cyan palette) | `ios/Caregiver/DesignSystem/Theme.swift` — still the **old blue** (see [[design-system]])                                      |

## Non-goals

- No custom blank-config screen in this pass (Custom card exists; its build is deferred).
- No per-field editor / add-remove-field UI in v1 — template fields are shown read-only (edit thresholds only).
- No tracker edit/archive here (separate flow; endpoints exist).
- `createTracker` is admin-only; caregivers don't see the New entry.
