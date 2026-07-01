# Settings

- **Module:** ios
- **Status:** Figma design pass **done** (main frame + create-care-group sheet + Settings Row / Toggle / Icon components + Tab Bar Settings-active variant) — next is the SwiftUI build.
- **Last updated:** 2026-07-01
- **Contract:** `GET /me` → `user{name,email}` + `memberships[]{care_group_id,name,role}`; `createCareGroup({name})` (`shared/openapi/openapi.yaml`). **Sign out is client-side** (Amplify/Cognito), not an API call.
- **Related specs:** [[team]] (sibling tab, same clone-the-frame + sheet build pattern), [[insights]], [[design-gallery]] (Stride design system), [[caretosher-post-login-ia]] (post-login IA + component library)

> **Read this before building Settings.** It captures the scope, the **contract reality** (what's wired vs designed-ahead), the resolved decisions, and the built Figma node IDs. The current `ios/Caregiver/Settings/…` screen is a placeholder. Design happened first in the **CareToSher Figma file**, then leads the SwiftUI build.

## Purpose

The **Settings** tab is the account/config surface: who you are, which care group is active (and creating/switching
groups), notification preferences, app/legal info, and sign-out. It's the 4th tab in the post-login IA.

## Requirements (from `WORKING.md` + IA)

1. **See the active care receiver / switch it** lives on Home; **care-group** membership (the tenant) is managed here —
   `Me.memberships` is an array, so switching/creating groups needs a home, and this is it.
2. **App-level config** users expect in Settings: notifications, about/legal, sign out.

## Backend reality (shapes the design)

- **`GET /me` is the only profile data** — `name` + `email`, no avatar → monogram-initial avatar (cyan ring on _you_).
  **No profile-edit or delete-account endpoint** → those are omitted, not faked.
- **`createCareGroup` is real** → the "Create care group" row opens a real sheet (Frame 2). A user can belong to
  **multiple care groups** (`memberships[]`); the active one is a **client-side selection** (no switch endpoint) — shown
  as a checkmark on the active row.
- **No notification-preferences endpoint** (B3b not built) → the **NOTIFICATIONS section is designed ahead of the
  contract**, flagged. Justified by the app's 2-week appointment-reminder requirement. Toggles are visual-only until a
  `notificationPreferences` endpoint exists (deferred backend item).
- **Sign out is client-side** Amplify `signOut()`.

## Resolved decisions (brainstorm 2026-07-01)

| #   | Decision                              | Choice                                                                                                                  | Why                                                                                  |
| --- | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1   | Tab scope                             | **Core + notifications**: profile · care groups (switch/create) · notifications (design-ahead) · about/legal · sign out | Covers what users expect; only notifications is ahead of contract.                   |
| 2   | Care-group switching home             | **In Settings**, as a checkmarked list of memberships + a Create row                                                    | `memberships[]` had no home; Home owns the _receiver_ switcher, not the _group_ one. |
| 3   | Notifications section                 | Include, **flagged design-ahead** (no prefs endpoint) — toggle rows                                                     | Real product need (appointment reminders); honest about the gap.                     |
| 4   | Profile edit / delete account / theme | **Omit v1** (no endpoints)                                                                                              | YAGNI; don't fake actions with no backend. See Non-goals.                            |
| 5   | Tab Bar Settings active-state         | Added `Active=Settings` variant to `Stride/Tab Bar`                                                                     | Set previously had Home/Insights/Team only.                                          |
| 6   | Create-care-group flow                | **Bottom sheet** (name field + Create button) over dimmed Settings                                                      | Mirrors [[team]]'s invite sheet; the one real action flow here.                      |

### Scope of the first Figma pass

- **Two frames:** **Settings main** (a **scroll artboard** — content taller than the 852 viewport, tab bar pinned to
  its bottom) and the **Create-care-group** sheet (over a dimmed, viewport-cropped Settings).
- **Sample data:** Trevor · `twilliams0095@gmail.com`; care groups _The Riverside Group_ (active ✓) + _Johnson Family_;
  notifications _Appointment reminders_ (on) / _Daily activity summary_ (off); About _Version 2.0.0_ + Privacy/Terms/Support.

## Design substrate — reuse, do not re-derive

Same Aurora substrate as [[insights]]/[[team]] — **read the [[insights]] substrate table** (palette variable IDs, type
ramp, glass-card recipe, glow ellipses). The Settings main frame was built by **cloning the Team overview frame** (bg
gradient, `Aurora Glow` ellipses, fonts, tab bar identical by construction), then the content container was cleared and
rebuilt as a hugging list and the frame resized into a scroll artboard.

## Components — reuse vs build

**Reuse (Stride/\*):** `Stride/Tab Bar` (now has `Active=Settings`) · `Stride/Field` `34:9` (group name) · `Stride/Button`
`24:6` (Create group). Section headers + profile header are inline (one-offs).

**Build new (added to Components section `84:4`):**

- `Stride/Settings Row` — variant set `Trailing = Chevron | None | Check | Value | Toggle`. Leading **`Icon`
  (INSTANCE_SWAP)** + **`Label` (TEXT)**; Value variant adds **`Value` (TEXT)**; Toggle variant embeds a `Stride/Toggle`.
- `Stride/Toggle` — iOS-style switch, `State = On | Off` (accent track + shadowed knob when on).
- `Stride/Icon` — variant set `Name = CareGroup | Plus | Bell | Shield | Doc | Help | Info | SignOut` (20px line icons,
  stroke bound to `text-secondary`), used as the swap target for the Settings Row `Icon` property.

### Build gotchas (for the SwiftUI build & future Figma edits)

- **Destructive (Sign out) is not a variant** — it's a `Trailing=None` row with a per-instance red override on the label
  fill + the swapped `SignOut` icon's vector strokes (`#ff4d6a`). Model row role→color in `Theme.swift`.
- **Instance children can't be `HUG`** — embedded instances (the toggle, the icon) keep their fixed size; only set
  `FILL`/`HUG` on frames and TEXT children (a `HUG` on the toggle instance threw and made the whole script no-op).
- The main frame is a **scroll artboard**: the `Content` container hugs (`primaryAxisSizingMode=AUTO`), the frame is
  resized to the content height, and the tab bar is repositioned to `height − 84` (pinned bottom).
- INSTANCE_SWAP default/override values are **component id strings** (e.g. the `Stride/Icon` variant id) — pass those to
  `setProperties`.

## Where it lives

### Built Figma nodes (file `qoiOteGuzktJPB6WKRbGHt`, page App Flow)

| Node                                                                                                                                                                         | ID        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `Settings` section                                                                                                                                                           | `159:584` |
| Main frame (`Settings · Main`, 393×961 scroll)                                                                                                                               | `159:585` |
| Create sheet frame (`Settings · Create care group`)                                                                                                                          | `161:665` |
| `Stride/Tab Bar` — added `Active=Settings` variant (set `112:196`)                                                                                                           | `155:568` |
| `Stride/Settings Row` — variant set (Chevron `158:568` · None `158:576` · Check `158:582` · Value · Toggle)                                                                  | `158:620` |
| `Stride/Toggle` — variant set (`State=On`/`Off`)                                                                                                                             | `156:572` |
| `Stride/Icon` — variant set (CareGroup `157:572` · Plus `157:575` · Bell `157:579` · Shield `157:582` · Doc `157:586` · Help `157:591` · Info `157:595` · SignOut `157:599`) | `157:600` |

| Concept                                           | Location                                                                                                                                      |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Design (lead)                                     | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Settings` section `159:584`; components → `Components` section `84:4`                   |
| iOS screen (placeholder today)                    | `ios/Caregiver/Settings/…`                                                                                                                    |
| Tokens (pending Theme.swift sync to cyan palette) | `ios/Caregiver/DesignSystem/Theme.swift` — still the **old blue**; adopting the Aurora palette is a known divergence (see [[design-gallery]]) |

## Non-goals

- No profile editing or delete-account in v1 (no endpoints).
- No real backend for **notification preferences** — designed ahead; needs a `notificationPreferences` endpoint (deferred).
- No group-switch endpoint — active group is a client-side selection.
- No appearance/theme picker (the app is single dark Aurora theme).
- Sign out is client-side Amplify, not an API call.
