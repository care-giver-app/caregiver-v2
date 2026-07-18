# iOS specs

Living, conceptual specs for the iOS app. See the repo-wide conventions in `../../CLAUDE.md`
(**Specs & plans**) and `../../docs/spec-template.md`. This README covers **layout** and the one rule
that keeps this folder from turning into spec hell.

## Layout

```
ios/specs/
  README.md          ← you are here
  sample-data.md     ← foundation: the ONE canonical fixture set (persona, roster, tracker hues)
  design-system.md   ← foundation: the ONE Stride component catalog + tokens + Theme.swift/Aurora state
  views/             ← one concise spec per screen or flow
    home · trackers · logging · insights · team · settings
    receivers · add-tracker · activity-timeline · event-detail · schedule
```

- **Foundation specs** (`sample-data.md`, `design-system.md`) live at the root — read them first; every
  view spec links to them via `[[sample-data]]` / `[[design-system]]`.
- **View specs** live in `views/`. Wiki-links are **name-based** (`[[home]]`, not a path), so specs move
  between folders freely without breaking cross-references.

## When do I write a new spec? (the anti-spec-hell rule)

**Figma is the design source of truth.** The spec layer is thin on purpose. Before adding a file, check:

- **Adding a Stride component** (Tab Bar, Member Row, Insight Card, a chart, a toggle…)? → **No new spec.**
  It's SwiftUI code + a Figma node + a **row in `design-system.md`**. Components multiply in code + Figma,
  not in markdown.
- **A component with real, non-obvious decision content** (a bespoke API, complex state, a data model like
  `StrideTimeline`'s `TimelineNode`)? → It _may_ earn its own file in a `components/` folder. Create that
  folder lazily, the first time it's actually needed — not before. This should be rare.
- **A new screen or multi-step flow**? → **Yes**, one concise spec in `views/`. One per screen/flow, **not**
  per SwiftUI subview.

A spec captures the _why_ (decisions, contract reality, gaps, honesty flags) — not a re-description of the
Figma frame or the code. If a would-be spec has no decisions in it, it shouldn't exist; put a row in the
catalog or a comment in the code instead.
