# C1-UI: Navigation Architecture

**Date:** 2026-06-18
**Scope:** App-wide navigation structure and information hierarchy
**Spec series:** C1-UI design pass

> **Refinement 2026-06-19:** Two changes folded in below — (1) the care team is now
> always visible on Home and the receiver switcher is scoped to the active team, and
> (2) tracker creation is made reachable (it was wired but orphaned). See the
> **Receiver switcher**, **Home empty state**, and **Settings** sections. Care team is
> _derived_ from the active receiver — there is no separate "active team" state (a
> receiver belongs to exactly one team, and multi-team users are rare).

---

## Design principle

The primary use case is a caregiver who opens the app multiple times a day to log something for
one person. The path to logging must be as short as possible. Management tasks (adding receivers,
editing trackers, team settings) are secondary and can be one level deeper.

---

## Tab bar structure

The app uses a 4-tab `TabView` as the top-level container inside `mainStack`. Tabs are added
incrementally — Home and Settings ship in C1-UI; Insights and Activity ship in C2.

| Tab          | Icon                        | C1-UI                                     | C2                                          |
| ------------ | --------------------------- | ----------------------------------------- | ------------------------------------------- |
| **Home**     | `house`                     | Active receiver + tracker cards + logging | Same                                        |
| **Insights** | `chart.line.uptrend.xyaxis` | Placeholder                               | Graphs, trends, averages, threshold history |
| **Activity** | `list.bullet`               | Placeholder                               | Cross-tracker chronological event feed      |
| **Settings** | `gearshape`                 | Team, receivers, account, sign out        | + notifications, invite management          |

Placeholder tabs for Insights and Activity ship with a simple "Coming soon" message so the tab bar
chrome is in place and no restructuring is needed when C2 builds those features.

---

## Active receiver — global state

The active receiver is **shared across all tabs**. Switching the receiver on Home automatically
updates what Insights and Activity show. There is no per-tab receiver selection.

**`ReceiverContext`** — an `@Observable` class injected at the `TabView` level via `.environment()`,
analogous to `Session`.

```swift
@Observable final class ReceiverContext {
    var receivers: [Receiver] = []
    var activeReceiverID: String?          // persisted via @AppStorage
    var activeReceiver: Receiver? {
        receivers.first { $0.receiverId == activeReceiverID } ?? receivers.first
    }
}
```

**Selection rules:**

- `activeReceiverID` persisted in `@AppStorage("activeReceiverID")`
- On first launch (no stored ID, or stored ID not found in current receivers list): auto-select
  `receivers.first`
- `ReceiverContext` loads the receiver list once on app launch; tabs read from it

---

## Screen hierarchy

```
TabView  ← injected: Session, ReceiverContext
  │
  ├── [Home] NavigationStack
  │     HomeView  ← root
  │       nav bar title (2 lines): [Receiver name ▾]
  │                                 Care team name (caption)
  │       │
  │       ├── TrackerDetailView   ← push, tap tracker card body
  │       │     └── EventDetailView   ← sheet, tap event row
  │       │
  │       ├── LogEventView   ← sheet, tap "+" on tracker card
  │       └── TemplatePickerView   ← sheet, admin "Add tracker" (empty state)
  │
  ├── [Insights] NavigationStack
  │     InsightsView  ← reads ReceiverContext.activeReceiver
  │
  ├── [Activity] NavigationStack
  │     ActivityView  ← reads ReceiverContext.activeReceiver
  │
  └── [Settings] NavigationStack
        SettingsView  ← two sections
          └── ReceiverDetailView   ← push, tap a receiver row (admin mgmt)
                ├── TemplatePickerView   ← sheet, "Add tracker"
                └── RenameSheet          ← sheet, rename receiver
```

---

## Receiver switcher

Lives in the nav bar title of `HomeView` only. Updates `ReceiverContext.activeReceiverID`, which
propagates to all other tabs automatically. The title is a **two-line block** so the care team is
always visible — you always know who you're logging for and which team it belongs to:

```
[The Williams Family ▾]   ← line 1: active receiver name + chevron.down (Menu trigger)
 Care Team Alpha          ← line 2: active team name (caption, ink @ 0.6)
```

The active **team name** is derived from the active receiver:
`memberships.first { $0.careGroupID == activeReceiver.careGroupId }?.name`. There is no separate
"active team" state.

**Dropdown — scoped to the active team.** The active team's receivers come first under a header;
other teams (rare) follow below a divider so a multi-team user is never stranded. An admin-only
**Add receiver** action sits at the bottom (reuses `AddReceiverView`), keeping the receiver-management
entry where you already pick receivers:

```
  ── Care Team Alpha            ← active team, header
     ● The Williams Family      ← checkmark on active
     ○ John Doe
  ──────────────────
  ── Care Team Beta             ← other teams (only if user has >1 team)
     ○ Jane Smith
  ──────────────────
  + Add receiver                ← admin only
```

If the user only has one receiver and is not an admin: chevron hidden, line 1 is a plain
non-interactive label (line 2 team caption still shows).

---

## Tracker card — dual tap targets

Each tracker on `HomeView` is a card with two distinct actions:

```
┌─────────────────────────────────┬────┐
│  ● [tracker color bar]          │    │
│  Tracker Name          caption  │ +  │
└─────────────────────────────────┴────┘
```

- **Card body tap** → push to `TrackerDetailView` (event history)
- **"+" button tap** → present `LogEventView` as a sheet

---

## Home empty state

When the active receiver has no trackers, the empty state depends on the caller's role in that
receiver's team:

- **Admin:** a primary **"Add tracker"** button → presents `TemplatePickerView(receiverId:)` for the
  active receiver; on save, Home reloads. This is the shortest first-run setup path.
- **Non-admin:** an informational message only ("No trackers yet" — no dead-end instruction to go
  somewhere they have no permission to act).

This replaces the previous `"No trackers yet. Add one in Settings."` message, which pointed to a
Settings screen that had no add-tracker action.

---

## Settings (tab 4)

Two clearly separated sections:

**Team & Receivers**

- Receivers are listed grouped by team. Each row is a `NavigationLink(value: Route.receiver(...))`
  that pushes `ReceiverDetailView` — the durable management surface (today its add-tracker / rename /
  archive actions are unreachable because nothing pushes `Route.receiver`; this wires it up).
- `ReceiverDetailView` (admin only): add tracker (template picker), rename receiver, archive receiver.
- Add receiver (admin only) — also available from the Home receiver dropdown.
- Future: rename team, manage members, send invites, rename/archive tracker.

**My Account**

- Signed in as {name} · {email}
- Face ID on/off (C2)
- Sign out

---

## What changes from current implementation

| Current                                                            | After                                                                                             |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `ReceiversListView` as `NavigationStack` root                      | `TabView` with 4 tabs; `HomeView` as Home stack root                                              |
| No tab bar                                                         | 4-tab `TabView` (Home + Insights placeholder + Activity placeholder + Settings)                   |
| Single `NavigationStack` for everything                            | Each tab has its own independent `NavigationStack`                                                |
| Person icon menu (sign out only)                                   | Dedicated Settings tab (two sections)                                                             |
| Navigate through receiver list on every open                       | Land directly on active receiver via `ReceiverContext`                                            |
| "Log reading" button at bottom of tracker detail                   | "+" on each tracker card on Home                                                                  |
| `EventDetailView` pushed onto nav stack                            | `EventDetailView` as a sheet                                                                      |
| No shared receiver state                                           | `ReceiverContext` injected via `.environment()`                                                   |
| Home title shows receiver name only                                | Two-line title: receiver name + active care team caption                                          |
| Dropdown lists all receivers (sections only if >1)                 | Dropdown scoped to active team first; other teams below a divider; admin "Add receiver" at bottom |
| Empty state: "Add one in Settings" (dead end)                      | Admin: "Add tracker" CTA → `TemplatePickerView`; non-admin: info message                          |
| `ReceiverDetailView` unreachable (nothing pushes `Route.receiver`) | Settings receiver rows push `ReceiverDetailView` (add tracker / rename / archive)                 |

---

## Build order

1. `ReceiverContext` — shared observable, load receivers, persist active ID
2. `HomeView` — tracker cards, receiver switcher, dual tap targets
3. `InsightsView` — placeholder
4. `ActivityView` — placeholder
5. `SettingsView` — two-section sheet
6. `TrackerDetailView` — updated toolbar, event history
7. `EventDetailView` — convert push → sheet
8. `LogEventView` — apply design language
9. `AddReceiverView` — apply design language

### Refinement work items (2026-06-19)

1. `HomeView` title → two-line block with active care team caption (derive team name from
   `me.memberships` via `activeReceiver.careGroupId`).
2. `HomeView` receiver dropdown → active team first, other teams below a divider, admin "Add receiver".
3. `HomeView` empty state → admin "Add tracker" CTA (`TemplatePickerView`) vs non-admin info message.
4. `SettingsView` receiver rows → `NavigationLink(value: Route.receiver(...))` into `ReceiverDetailView`.
   (No `ReceiverDetailView` changes needed — it already has add tracker / rename / archive.)
