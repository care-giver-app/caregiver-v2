# Post-login shell (tabs + ⊕ FAB)

- **Module:** ios
- **Status:** SwiftUI build **done** (this branch's PR) — designed 2026-07-05, built same day.
- **Last updated:** 2026-07-05
- **Contract:** none of its own — the shell hosts tabs; each tab's spec lists its endpoints.
- **Related specs:** [[home]] · [[insights]] · [[team]] · [[settings]] (the four tabs), [[logging]] (the ⊕ FAB's eventual target), [[design-system]] (`StrideTabBar`, backgrounds)

## Purpose

The post-login frame: four tabs (`Home · Insights · Team · Settings`) split around the raised ⊕
quick-log FAB, rendered by `StrideTabBar`. Replaces the old system `TabView` IA (which had a
standalone Activity tab — now folded into Home as the Today timeline widget).

## Behavior

- **Structure:** keep the system `TabView` underneath for per-tab state preservation and lazy
  loading, hide its bar (`.toolbar(.hidden, for: .tabBar)`), and overlay `StrideTabBar` bound to
  `StrideTab`. Each tab keeps its own `NavigationStack`; tab content pads its bottom safe area so
  scroll content clears the custom bar.
- **⊕ FAB (interim):** presents a plain tracker-picker sheet for the active receiver → the existing
  `LogEventView` dynamic form. Deliberately unstyled — the whole sheet is replaced by the Aurora
  quick-log wizard ([[logging]]) in that pass. A successful log reloads Home's data.
- **Interim tab content:** Insights keeps its placeholder view; Settings keeps the current
  functional (pre-Aurora) `SettingsView`; Team shows a `StrideEmptyState` until its build pass.
- **Background:** all post-login screens sit on the Aurora night substrate (no auth glow ellipses —
  see [[design-system]]).

## Key decisions

| #   | Decision              | Choice                                                                           | Why                                                                                             |
| --- | --------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| 1   | Bar hosting           | System `TabView` + hidden bar + `StrideTabBar` overlay, not a hand-rolled ZStack | Free per-tab state preservation + lazy tab loading; only the chrome deviates from the system.   |
| 2   | Activity tab          | Removed — its model/logic live on as Home's timeline widget                      | Post-login IA (2026-06-30): Today + Activity were ~80% the same screen.                         |
| 3   | FAB before the wizard | Real interim behavior (tracker picker → existing log form), not hidden or inert  | 2026-07-05 (Trevor): keep the signature IA element functional; wizard swaps in wholesale later. |
| 4   | Interim tabs          | Keep existing Insights/Settings views; Team = Aurora empty state                 | 2026-07-05 (Trevor): don't strand working Settings functionality behind a coming-soon screen.   |

## Where it lives

| Concept                | Location                                              |
| ---------------------- | ----------------------------------------------------- |
| Shell (tab host + FAB) | `ios/Caregiver/App/RootView.swift` (`mainStack`)      |
| Tab bar component      | `ios/Caregiver/DesignSystem/StrideTabBar.swift`       |
| Design (lead)          | Figma `qoiOteGuzktJPB6WKRbGHt` → `Stride/Tab Bar` set |

## Non-goals

- No Aurora rebuilds of Insights/Team/Settings here — each gets its own pass ([[insights]], [[team]], [[settings]]).
- No quick-log wizard — the FAB's interim sheet is a placeholder for [[logging]].
