# Care receivers — switch & add

- **Module:** ios
- **Status:** Figma design pass **done** (switch sheet + add sheet + Receiver Row component + Calendar icon) — next is the SwiftUI build.
- **Last updated:** 2026-07-01
- **Contract:** `listReceivers(careGroupId)` → `Receiver{receiver_id,name,date_of_birth?,archived,…}`; `createReceiver(careGroupId,{name,date_of_birth?})` **admin-only**; `getReceiver` / `updateReceiver` / `archiveReceiver` exist (`shared/openapi/openapi.yaml`). **Active receiver is a client-side selection** (no endpoint).
- **Related specs:** [[settings]] (same switch+create pattern for care groups), [[team]], [[insights]], [[design-gallery]] (Stride design system), [[caretosher-post-login-ia]] (post-login IA)

> **Read this before building.** It captures the two connected pieces (switch + add), the contract reality, resolved
> decisions, and the built Figma node IDs. The **switcher trigger already exists** on Home (`ReceiverSwitcher` header
> `54:4` — monogram + name + chevron.down + care-group subtitle); this pass designs **what the chevron opens** and the
> **add flow**. Design happened in the CareToSher Figma file, then leads the SwiftUI build.

## Purpose

A `CareGroup` owns one or more **receivers**; each receiver owns its own trackers/events. A caregiver works "on" one
active receiver at a time and needs to **switch** between them and **add** new ones. The active receiver scopes Home,
Insights, Activity, and logging.

## Backend reality (shapes the design)

- **`Receiver` has `name` + optional `date_of_birth` + `archived`; no photo** → monogram avatars; **age derived from
  `date_of_birth`** (blank when absent).
- **`createReceiver` is admin-only** → the "+ Add care receiver" entry and Add sheet are admin-gated; the **switch list
  is visible to all members**.
- **Active receiver is client-side** (no "set active" endpoint) — selection updates the Home header locally (signature
  recency-glow), no network write.
- `updateReceiver` / `archiveReceiver` exist but **edit/archive is deferred** — v1 is switch + add only.

## Resolved decisions (brainstorm 2026-07-01)

| #   | Decision              | Choice                                                | Why                                                                                                                  |
| --- | --------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1   | Switcher presentation | **Bottom sheet** from the Home header chevron         | Consistent with every other sheet (quick-log, invite, create-group); scales to many receivers; room for the Add row. |
| 2   | Receiver row content  | **Hue monogram + name + age**, active row checkmarked | Per-receiver hue aids at-a-glance recognition of who you're on; age is the useful elder-care meta.                   |
| 3   | Per-receiver color    | **Tracker hues** (cyan/teal/violet) on the monogram   | Reuses the existing hue palette; the one accent moment.                                                              |
| 4   | Add fields            | **Name (required) + Date of birth (optional)**        | Matches `CreateReceiverRequest` exactly.                                                                             |
| 5   | Edit / archive        | **Defer** (endpoints exist) — v1 = switch + add       | YAGNI; keep the switcher fast. See Non-goals.                                                                        |
| 6   | Add gating            | Admin-only Add; all members can switch                | `createReceiver` is admin-only.                                                                                      |

### Scope of the first Figma pass

- **Two frames, both over a dimmed Home** (where the switcher lives): the **Switch** sheet and the **Add** sheet.
- **Sample data:** Eleanor (72, active, cyan) · Harold (78, teal) · Rosa (69, violet) · group "Mom's Care Team".

## Design substrate — reuse, do not re-derive

Same Aurora substrate as [[insights]]/[[team]]/[[settings]] — **read the [[insights]] substrate table**. Both frames
were built by **cloning the Home frame** (`53:3`) for a real dimmed background (header + trackers + timeline + tab bar),
then adding a scrim + bottom sheet — the same clone-a-prior-frame pattern used across the tab designs.

## Components — reuse vs build

**Reuse:** sheet shell, `Stride/Field` `34:9` (name / DOB — DOB's icon **instance-swapped** to `Stride/Icon` Calendar),
`Stride/Button` `24:6` (Add receiver), `Stride/Settings Row` `158:620` (the "+ Add care receiver" row — Chevron + Plus
icon), tab bar (Home-active, already on the dimmed bg).

**Build new:**

- `Stride/Receiver Row` — variant set `State = Active | Default`. Hue-wash monogram (`hue-bg` + `Initial`) + name + age;
  Active adds a trailing accent check. TEXT props `{Name, Initial, Age}`. Per-receiver hue = a per-instance override of
  `hue-bg` fill + `Initial` fill.
- **`Calendar`** icon added to the `Stride/Icon` set (for the DOB field).

### Build gotchas (for the SwiftUI build & future Figma edits)

- **Variable-bound paint opacity does NOT survive instance derivation** — a `hue-bg` bound to `aurora/cyan` at 0.18
  rendered as a solid disc on instances (opacity reset to 1). **Use a raw solid at 0.18** for the hue wash, not a
  bound-variable paint with reduced opacity. (Bound paint is fine at full opacity.)
- `Stride/Field`'s leading icon is an **INSTANCE_SWAP** that accepts any component — swapping in a `Stride/Icon` variant
  (Calendar) works.
- The switcher **trigger** is the existing Home `ReceiverSwitcher` (`54:4`) — unchanged this pass.

## Where it lives

### Built Figma nodes (file `qoiOteGuzktJPB6WKRbGHt`, page App Flow)

| Node                                                                                       | ID        |
| ------------------------------------------------------------------------------------------ | --------- |
| `Receivers` section                                                                        | `168:750` |
| Switch frame (`Receivers · Switch`, sheet over dimmed Home)                                | `168:751` |
| Add frame (`Receivers · Add`, sheet over dimmed Home)                                      | `170:852` |
| `Stride/Receiver Row` — variant set (`State=Active` `166:750` · `State=Default` `166:759`) | `166:768` |
| `Stride/Icon` → added `Name=Calendar` variant (set `157:600`)                              | `165:753` |

| Concept                                           | Location                                                                                                                     |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Design (lead)                                     | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Receivers` section `168:750`; components → `Components` section `84:4` |
| Switcher trigger (exists)                         | Home frame `53:3` → `ReceiverSwitcher` `54:4`                                                                                |
| iOS screen (placeholder today)                    | `ios/Caregiver/Home/…` (switcher) + a receivers model                                                                        |
| Tokens (pending Theme.swift sync to cyan palette) | `ios/Caregiver/DesignSystem/Theme.swift` — still the **old blue** (see [[design-gallery]])                                   |

## Non-goals

- No edit/rename or archive in v1 (endpoints exist; deferred).
- No "set active receiver" endpoint — active is client-side.
- No receiver photos (no field) — monogram avatars.
- No per-receiver caregiver assignment (membership is group-scoped).
