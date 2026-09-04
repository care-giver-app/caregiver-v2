# C1 — iOS MVP + Design Language

- **Status:** Draft
- **Date:** 2026-06-12
- **Deciders:** Trevor Williams
- **Roadmap phase:** C1 (see `docs/roadmap.md`) — primary / first client
- **Builds on:** B1 (identity), B3a (core care domain API), ADR-0009 (SwiftUI iOS)

## 1. Purpose

Ship the first **usable** Caregiver v2 client: a native SwiftUI iOS app on fresh data. A caregiver
can sign in, create a care group, add a receiver, define trackers from seeded templates, **log
events against a tracker, and view history** — consuming the generated `CaregiverAPI` Swift client
from B3a. C1 also establishes the app's **design language** as a reusable token system.

This is the payoff of sequencing B3a first: the app is built entirely against the contract we
already shipped, with no backend changes required.

## 2. Context

`ios/` is greenfield. B3a delivered the synchronous API (Receivers, Trackers, Events, the
tracker-template catalog) and generated a Swift client package, `shared/types-swift` (`CaregiverAPI`),
that produces typed request methods + a `Client` from `openapi.yaml` via Apple's
`swift-openapi-generator`, over `OpenAPIURLSession`. B1 established Cognito (email-as-username, SRP,
public app client, no secret) and the rule that clients must send the **ID token** (it carries
`email`/`name`; access tokens don't).

Toolchain: Xcode 26.2, Swift 6.2, **iOS 17+** target (ADR-0009).

### 2.1 Decisions locked during brainstorming

| Decision           | Choice                                                                                              |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| Auth stack         | **Amplify Swift (Auth category), headless** + custom SwiftUI screens; ID token → bearer middleware  |
| App pattern        | **Plain SwiftUI + `@Observable`** (the "MV" pattern); no MVVM/TCA                                   |
| Project definition | **XcodeGen** (`project.yml`); generated `.xcodeproj` is gitignored                                  |
| Design direction   | **"Clinical & Clean"** — white grouped cards, navy text, one blue accent, color-coded tracker edges |
| Design tokens      | Centralized **semantic `Theme`** tokens, asset-catalog-backed; components reference tokens only     |
| Onboarding         | **Create-group only** (accept-invite deferred to C2)                                                |
| Event edit/delete  | **In scope**                                                                                        |
| Manage structure   | **Rename / archive receivers & trackers** in scope (admin)                                          |
| Tracker creation   | **Clone a seeded template**; the full custom field-schema builder is C2                             |
| Connectivity       | **Online-only** (no offline cache/queue)                                                            |

## 3. Goals

- A native iOS app that runs the full mandatory chain on fresh data: **sign up/in → create group →
  add receiver → create tracker from a template → log an event → view history.**
- Reuse the **generated `CaregiverAPI` client** unchanged; no backend or contract changes in C1.
- Authentication via **Amplify Auth** against the existing Cognito pool, attaching the **ID token** to
  every request through one client middleware — no screen ever touches tokens.
- A **dynamic event-logging form** generated from a tracker's `fields` schema (number/text/boolean/
  enum/datetime), with client-side validation mirroring the server.
- A **reusable design system** (`Theme` tokens) so the look is consistent and a future rebrand or dark
  theme is a token change, not a component rewrite.
- A reproducible project (**XcodeGen**) and a lean **macOS CI** job (unit tests + compile, path-gated).

## 4. Non-Goals (deferred)

- **Custom tracker builder** (author/edit a field schema in-app) → **C2**. C1 clones seeded templates.
- **Accept-invite onboarding** (`GET /invitations/mine` + accept by token) → **C2**. C1 creates groups.
- **APNs push**, **breach badge UI**, **schedules/reminders**, **notification preferences**,
  **analytics/charts**, **audit viewer** → C2 / B2 / B3b. (The breach `Theme.Colors.alert` token is
  reserved now; the badge ships in C2.)
- **Sign in with Apple** → C2 (federated into Cognito; B1 deferred the Apple "Hide My Email" handling).
- **Offline support** (cache/queue/sync) → later.
- **The empty/loading/error _polish_ pass** (skeleton loaders, illustrations, refined copy) → C2.
  Functional loading/empty/error states are in C1.
- **iPad-optimized layouts, widgets, UI-test automation, snapshot tests** → later.

## 5. Architecture & project structure

**The spine.** A single `Session` (`@Observable`), injected via SwiftUI `@Environment`, owns the
cross-cutting state: Amplify auth status, the configured `CaregiverAPI.Client`, and the bootstrapped
`Me` (current user + memberships). Each feature screen has its own lightweight `@Observable` model
that calls the client and holds only that screen's state. The generated `Client` is the service
layer; a per-screen model calling it directly is the leanest testable unit. (Extracting repositories
is a clean later refactor if the app grows.)

**Single module** for C1 (one app target); the folders below are groups, not separate SPM modules.

```
ios/
  project.yml                 # XcodeGen spec (source of truth; .xcodeproj gitignored)
  Caregiver/
    App/                      # CaregiverApp entry, Session, @Environment wiring
    Auth/                     # Amplify config + sign-in/up/confirm screens & model
    Onboarding/               # create-first-group gate
    Dashboard/                # receivers list, receiver detail (trackers)
    Trackers/                 # template picker, tracker detail
    Events/                   # dynamic log form, history list, edit/delete
    DesignSystem/             # Theme tokens + reusable components
    Support/                  # Session, API client factory, auth middleware, error mapping
  CaregiverTests/             # unit tests
```

**Dependencies** (via `project.yml`): the local `CaregiverAPI` package (`shared/types-swift`) and
**Amplify Swift**. The app builds the generated `Client` against a per-stage base URL (from an
`.xcconfig` build setting) and wraps it with an **auth middleware** (`ClientMiddleware`) that fetches
the current ID token from Amplify and sets `Authorization: Bearer …` on every request.

## 6. Auth & session

**Amplify configuration.** Because Cognito was built with raw CDK (not an Amplify backend), we
hand-author `amplifyconfiguration.json` pointing Amplify Auth at the existing pool — `PoolId`,
`AppClientId`, `Region` — one file per stage (dev/prod), selected by build config. Those values come
from the CDK outputs (`UserPoolId`, `UserPoolClientId`). Amplify drives Cognito with no backend
provisioning on its side.

**Flows** (custom SwiftUI screens, Amplify under the hood):

- **Sign up** — email + password → `Amplify.Auth.signUp` → Cognito emails a code → **confirm-code
  screen** → `confirmSignUp`. (Pool has self-signup + email auto-verify; password policy ≥8 chars w/
  lowercase + digit, validated client-side.)
- **Sign in** — email + password → `Amplify.Auth.signIn` (SRP). An unconfirmed user routes back to the
  confirm-code screen.
- **Sign out** — `Amplify.Auth.signOut`; clears `Session`.

**Token → bearer.** The auth middleware calls `fetchAuthSession` and injects the **ID token** (not the
access token) on every `CaregiverAPI` request. Amplify owns refresh + Keychain storage.

**Session lifecycle & bootstrap gate.** On launch `Session` asks Amplify whether a user is signed in:

- **Not signed in** → Auth screens.
- **Signed in** → call **`GET /me`** (triggers server-side JIT provisioning of the `user` row). The
  response decides the first screen: `memberships == []` → **Onboarding** (create group); otherwise →
  **Dashboard**.

`Session` is a small state machine: `.checking` · `.signedOut` · `.onboarding(Me)` · `.ready(Me)`.
A 401 anywhere resets to `.signedOut` (safety net; Amplify refresh normally prevents it).

## 7. Screen map & navigation

Root view switches on `Session` state. The main app is a single `NavigationStack` drilling down the
domain hierarchy:

```
ReceiversList (root)              ← GET /receivers (across the caller's groups)
│   toolbar: [＋ receiver]ᴬ   [account ▾ → sign out]
│   • sectioned by care group if >1; empty state → "Add a receiver"
└─▸ ReceiverDetail                ← GET /receivers/{id}/trackers
    │   toolbar: [＋ tracker]ᴬ   [edit ▾ → rename / archive]ᴬ
    └─▸ TemplatePicker (＋ tracker)   ← GET /tracker-templates → POST tracker
    └─▸ TrackerDetail                 ← GET /trackers/{id}/events (paginated)
        │   primary: [Log reading]   toolbar: [edit ▾ → rename / archive]ᴬ
        │   • history list, loads more via next_cursor
        └─▸ LogEvent (dynamic form)   ← POST event
        └─▸ EventDetail → edit / delete  ← PATCH / DELETE event
```

ᴬ = **admin-only affordance**, gated by `Me.memberships[careGroupId].role`. Admins add/rename/archive
receivers & trackers; **all members** log/edit/delete events and read everything. Non-admins simply
don't see the gated toolbar items.

**Dynamic LogEvent form** (the core): reads `tracker.fields` and renders an input per `type` — number
(decimal pad + unit label), text, boolean (toggle), enum (picker from `options`), datetime — plus
`occurred_at` (defaults to now) and an optional note. The same form, prefilled, backs event editing.

**Add-receiver target group:** implicit if the caller is in one group, a small group picker if
several. Onboarding always creates the first group, so the main app is never zero-group.

## 8. Design language

**Direction: "Clinical & Clean."** White grouped cards on a cool-gray background, navy text, a single
blue accent, hairline borders, 12px corners, comfortable density; the system font (SF Pro). Each
tracker row carries a **color-coded left edge** driven by that tracker's own `color` field.

**Token system (hard rule): components reference semantic tokens only — never raw hex or magic
numbers.** A central `Theme` layer:

- `Theme.Colors` — `accent`, `textPrimary`, `textSecondary`, `textTertiary`, `surface`, `background`,
  `border`, `alert` (reserved for the C2 breach badge), `success`.
- `Theme.Spacing` — a 4-pt scale (`xs`/`sm`/`md`/`lg`).
- `Theme.Radius` — `card`, `control`.
- `Theme.Typography` — `largeTitle`, `title`, `headline`, `body`, `subhead`, `caption`.

Tokens are named by **role, not appearance** (`accent`, not `blue`), and the color tokens are backed
by **Asset Catalog color sets**, so each can carry light + dark values — adding a dark theme later
needs **zero component changes**. A rebrand is a one-file token edit.

The **per-tracker edge color** comes from the tracker's `color` field in the API _data_ (parsed
hex → `Color` at runtime) and is deliberately separate from the brand tokens, so user-chosen tracker
colors (C2) never collide with the theme.

## 9. State, errors & validation

**Per-screen state.** Each screen model exposes one status: `loading` → `loaded(data)` / `empty` /
`error(message)`. Lists support pull-to-refresh; the history list pages via `next_cursor` on scroll.
Mutations show inline progress and disable their control, then refresh or pop.

**Error mapping (one layer).** The generated client returns a typed enum per HTTP status. A small
`AppError` mapper turns non-success into a friendly message: 400 → surface the server's message (e.g.
"systolic is required"); 403 → "You don't have permission"; transport failure → "No connection — try
again". Amplify auth errors map the same way. A 401 resets `Session` to signed-out.

**Validation mirrors the server.** The dynamic form runs the same rules as the backend's
`ValidateValues` (required present, type, enum membership) to catch mistakes before the round-trip;
the server stays the source of truth (a server 400 still shows inline).

**Online-only** — every screen fetches fresh; no cache/queue in C1.

## 10. Testing strategy

Testing-trophy (ADR-0006), adapted to iOS — fast unit tests carry the weight (no simulator/network):

- **Unit (bulk):** the dynamic-form builder (`fields → input config`), the client-side validation
  mirror, the **auth middleware** (stamps the bearer correctly), the `AppError` mapper, hex→`Color`
  parsing, and the `Session` state-machine transitions.
- **Client package:** the existing `CaregiverAPI` build + `getHealth` live-smoke pattern; optionally a
  decode test that our models parse the API shapes.
- **Skip for C1:** XCUITest UI automation and snapshot tests (slow/brittle).
- **Manual:** one end-to-end on the simulator against dev (sign up → create group → add receiver →
  tracker → log → history).

## 11. CI

Extend `.github/workflows/ci-pr.yml` with a **macOS** job, **path-gated to `ios/**` and the Swift
client\*\* (macOS runners are slower/pricier than Linux — don't pay for them on backend-only PRs):

- `xcodegen generate` → `xcodebuild test` (unit tests, one simulator) + an app compile.
- Optionally `swift build`/`test` for the `CaregiverAPI` package.

## 12. Open questions / forward constraints

- **Sign in with Apple (C2)** — Amplify supports federating SIWA into Cognito; revisit Apple
  private-relay email capture (B1's open question) when added.
- **Accept-invite (C2)** — `GET /invitations/mine` + accept-by-token; the API already exists.
- **Custom tracker builder (C2)** — authoring a field schema in-app; the `Tracker`/`Field` contract
  already supports it.
- **Dark theme** — not designed in C1, but the asset-catalog-backed tokens make it additive.
- **Offline** — online-only now; a cache/queue layer is a later, isolated addition behind the same
  screen models.
- **Stage config** — dev/prod base URL + Amplify config selected by build config; the values come
  from CDK outputs and must be wired during implementation.

## 13. Success criteria

C1 is complete when:

- The app builds via `xcodegen generate` + `xcodebuild`, targets iOS 17+, and depends on the local
  `CaregiverAPI` package + Amplify.
- A real user can **sign up, confirm, sign in**, and — with zero memberships — **create a care group**,
  then **add a receiver, create a tracker from a template, log a measurement event, and page through
  time-ordered history**, against the dev API.
- Admin-only affordances (add/rename/archive receivers & trackers) are correctly gated by role; all
  members can log/edit/delete events.
- The dynamic form renders and validates every field type; a server 400 surfaces inline.
- The design system is centralized in `Theme` tokens; no component hard-codes a hex/number.
- Unit tests pass locally and in the path-gated macOS CI job.
- One manual end-to-end against dev passes.
