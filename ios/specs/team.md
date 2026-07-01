# Team

- **Module:** ios
- **Status:** Figma design pass **done** (overview + invite-sheet frames + Member Row / Invite Card components + Tab Bar Team-active variant) — next is the SwiftUI build.
- **Last updated:** 2026-07-01
- **Contract:** `listMembers(careGroupId)` → `Member{user_id,name,role}`; `createInvitation(careGroupId,{email,role})` → `Invitation{token,role,expires_at}`; `revokeInvitation(careGroupId,token)`; invitee side is `listMyInvitations` (`shared/openapi/openapi.yaml`). **No group-level "list pending invitations" endpoint exists** — only create + revoke-by-token.
- **Related specs:** [[insights]] (sibling tab, same clone-the-overview build pattern), [[design-gallery]] (Stride design system), [[caretosher-post-login-ia]] (post-login IA + Figma component library), [[activity-timeline]]

> **Read this before building Team.** It captures the requirements, the **contract reality that shapes the whole tab** (invites are token-first, no email is ever sent), the resolved design decisions, and the built Figma node IDs. The current `ios/Caregiver/Team/…` screen is a placeholder. Design happened first in the **CareToSher Figma file**, then leads the SwiftUI build.

## Purpose

The **Team** tab answers _"who is in this care group, and how do I add someone?"_ — a member roster plus an
admin-only invite flow. It complements Home (which shows a face-pile of the team) with the full roster and the
one place invites are created. Scoped to the caller's active `CareGroup`.

## Requirements (from `WORKING.md`)

1. **See other caregivers in the group** — roster with name + role.
2. **Invite another caregiver** — admin-only; produces a shareable invite.

## Backend reality (shapes the design)

- **Invites are token-first; no outbound email** (per B1 / CLAUDE.md). `createInvitation` returns a `token` + `expires_at`;
  the admin **shares that token/link out of band** (iOS share sheet). Admin-role invites require the accepting email to
  match; caregiver invites are token-first (supports Apple "Hide My Email"). Invitees discover invites via
  `GET /invitations/mine`, not email. → The invite flow's _output_ is a **shareable code card**, not a "sent" confirmation.
- **`listMembers` returns only `{user_id, name, role}`** — no email, avatar, or `last_active`. So: monogram avatars from
  initials (no photos), and **no faked presence/online glow** (there's no timestamp behind it). Same "don't pretend the
  data exists" rule [[insights]] followed for analytics.
- **No group-level pending-invite read endpoint.** The **PENDING section is designed ahead of the contract** — flag it;
  a `listInvitations(careGroupId)` endpoint (or reusing the created-invite response) is a **deferred backend item**.
- Roles are fixed `admin | caregiver`; **no remove-member or change-role endpoint** → those are out of scope (Non-goals).

## Resolved decisions (brainstorm 2026-07-01)

| #   | Decision                    | Choice                                                                                                                                   | Why                                                                                               |
| --- | --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| 1   | Tab scope                   | **Roster + invite + pending section**                                                                                                    | Everything but pending has a real endpoint; pending is design-ahead, flagged.                     |
| 2   | Invite flow form            | **Bottom sheet → invite card** (role toggle + optional email → Generate → revealed shareable code card + Share)                          | Matches the existing quick-log sheet pattern; shows the whole token-share story in one artboard.  |
| 3   | Member identity viz         | Monogram initials (no photos); **admin = accent, caregiver = quiet secondary**; the current user gets a cyan avatar **ring + "You" tag** | Honest to the payload; spends the accent "boldness" once on role/identity, not on faked presence. |
| 4   | Pending section             | Include, **flagged design-ahead** (no read endpoint) — email + `Invited · expires 7d` + revoke ✕                                         | Users expect to see/cancel outstanding invites; note the backend gap.                             |
| 5   | Tab Bar Team active-state   | Added `Active=Team` variant to `Stride/Tab Bar` before reuse                                                                             | Set previously baked only Home/Insights.                                                          |
| 6   | Remove member / change role | **Defer** — no endpoint                                                                                                                  | YAGNI; see Non-goals.                                                                             |

### Scope of the first Figma pass

- **Two frames:** the **Team overview** (roster + pending + invite CTA) and the **Team invite** sheet (over a dimmed
  overview, shown in its post-generate state so the form _and_ the resulting code card are both visible).
- **Sample data — realistic care group:** "The Riverside Group" · Trevor (You, Admin) · Dana (Caregiver) · Marcus
  (Caregiver) · 1 pending caregiver (`jordan@email.com`, `expires 7d`).

## Design substrate — reuse, do not re-derive

Same Aurora substrate as [[insights]] — **do not re-derive it, read that spec's substrate table** (palette variable IDs,
type ramp, glass-card recipe, glow ellipses). Both Team frames were built by **cloning the Insights overview frame** so
the gradient bg, two `Aurora Glow` ellipses, fonts, glass-card styling, and tab bar are identical by construction.
Palette bindings used here: `color/auth/{surface,surface-hi,border,accent,text-primary,text-secondary,text-tertiary}`.

## Components — reuse vs build

**Reuse (Stride/\*):** `Stride/Tab Bar` (now has `Active=Team`) · `Stride/Section Header` pattern (the `MEMBERS`/`PENDING`
labels) · `Stride/Chip` `90:85` (role toggle Caregiver/Admin) · `Stride/Field` `34:9` (email) · `Stride/Button` `24:6`
(Generate invite / Invite caregiver / Share link).

**Build new (added to Components section `84:4`):**

- `Stride/Member Row` — variant set `State=Active | Pending`. Active = monogram avatar (with a boolean-toggled cyan
  **ring**) + name + boolean-toggled **You** tag + role badge. Pending = mail-glyph avatar + email + `Meta` line + role
  badge + revoke ✕. TEXT props: Active `{Name, Initial, Role}` + BOOLEAN `Is You`; Pending `{Email, Meta, Role}`.
- `Stride/Invite Card` — the signature shareable element: `INVITE CODE` label + mono `Code` (Space Grotesk) + `expiry`
  pill + a reused primary **Share link** button; accent-tinted border + soft cyan glow. TEXT props `{Code, Expiry}`.

### Build gotchas (learned this pass — for the SwiftUI build & future Figma edits)

- **Role color is not a component property.** The Active component's role text is `accent` (admin); caregiver rows get a
  **per-instance fill override** to `text-secondary`. Model role→color in `Theme.swift`, not as a variant.
- **`combineAsVariants` merges same-named properties.** Active `Role` (default "Admin") and Pending `Role` merged into one
  property, so the pending instance inherited "Admin" until overridden — set each instance's `Role` explicitly.
- **`setBoundVariableForPaint` returns a frozen paint;** bake `opacity` into the input paint object _before_ binding
  (mutating `.opacity` after silently no-ops → the "You" wash rendered as solid cyan on the first attempt).
- Instances snapshot fills as overrides at creation — instances created _before_ a main-component fill fix don't inherit
  it; re-apply on the instance.

## Where it lives

### Built Figma nodes (file `qoiOteGuzktJPB6WKRbGHt`, page App Flow)

| Node                                                                                     | ID        |
| ---------------------------------------------------------------------------------------- | --------- |
| `Team` section                                                                           | `146:414` |
| Overview frame (`Team · Overview`, 393×852)                                              | `146:415` |
| Invite frame (`Team · Invite`, sheet over dimmed overview)                               | `150:484` |
| `Stride/Tab Bar` — added `Active=Team` variant (set `112:196`)                           | `138:413` |
| `Stride/Member Row` — variant set (`State=Active` `143:413` · `State=Pending` `144:413`) | `144:427` |
| `Stride/Invite Card`                                                                     | `145:421` |

| Concept                                           | Location                                                                                                                                      |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Design (lead)                                     | Figma `qoiOteGuzktJPB6WKRbGHt` → **App Flow** page → `Team` section `146:414`; components → `Components` section `84:4`                       |
| iOS screen (placeholder today)                    | `ios/Caregiver/Team/…`                                                                                                                        |
| Tokens (pending Theme.swift sync to cyan palette) | `ios/Caregiver/DesignSystem/Theme.swift` — still the **old blue**; adopting the Aurora palette is a known divergence (see [[design-gallery]]) |

## Non-goals

- No remove-member or change-role in v1 (no endpoint).
- No real backend for the **pending list** — designed ahead; needs a `listInvitations(careGroupId)` endpoint (deferred).
- No outbound email — invites are token-first, shared via the iOS share sheet.
- No per-receiver caregiver assignment (membership is group-scoped, not receiver-scoped).
- No faked presence/online indicators (no `last_active` in the payload).
