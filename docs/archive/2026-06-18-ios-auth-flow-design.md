# iOS Auth Flow Design

**Date:** 2026-06-18
**Scope:** Auth landing, sign-in, sign-up, Face ID biometric re-auth, enrollment offer

---

## Goal

A single, consistent auth landing page that is always the entry point for unauthenticated users.
Face ID integration is invisible when it works — the landing page layout never changes based on
enrollment state.

---

## Auth entry reasons

Two distinct reasons a user ends up on the auth flow:

| Reason                | Source                                                       | Face ID auto-attempt? |
| --------------------- | ------------------------------------------------------------ | --------------------- |
| **Session expired**   | `session.refresh()` fails on app launch or background resume | Yes, if enrolled      |
| **Explicit sign-out** | User tapped "Sign out"                                       | No                    |

The `Session` object must track which reason caused the signed-out state so the landing page can
decide whether to attempt Face ID.

---

## Screens

### `AuthLandingView`

Always shown first when `session.state == .signedOut`. Layout never changes.

- Logo (centered, scaledToFit)
- `PrimaryButton("Sign In")` → navigates to `SignInView`
- `GlassButton("Create Account")` → navigates to `SignUpView`
- Support link

**Face ID behavior (on appear, if session expired — not explicit sign-out):**

- If `faceIDEnabled == true` AND `BiometricAuth.isAvailable`: attempt silently in background
- Success → `session.refresh()` picks up the new session → `RootView` navigates to `mainStack`
- Failure / denial / no credentials → do nothing; buttons are always available

The landing page content does not show a Face ID button, spinner, or any indicator of the attempt.
It just works if it works.

### `SignInView`

Email + password form. Shown when user taps "Sign In" from landing.

- GlassField: email (autocapitalization off, email keyboard)
- GlassField: password (secure)
- Remember me toggle (`@AppStorage`)
- Forgot password link → `ForgotPasswordView` sheet
- `PrimaryButton("Sign In")`
- `GlassButton("Sign in with Face ID", icon: "faceid")` — only visible if `faceIDEnabled == true`
  - Tapping triggers `BiometricAuth.authenticate()` then `signInWithBiometrics()` if granted
- Back → returns to `AuthLandingView`
- Support link

### `SignUpView`

New account creation. Shown when user taps "Create Account" from landing.

- GlassField: first name, last name (HStack)
- GlassField: email
- GlassField: password, confirm password
- `PrimaryButton("Create Account")`
- Back → returns to `AuthLandingView`
- Support / Terms / Privacy links

After successful sign-up → flows through email confirmation (`ConfirmCodeView` sheet) → auto
sign-in → same post-sign-in path as manual sign-in.

### `ConfirmCodeView` (sheet)

Email confirmation code entry. Presented as `.medium` sheet over `SignUpView` (and `SignInView`
if confirmation is required there). Dismisses automatically when confirmed.

### `ForgotPasswordView` (sheet)

Two-step: email entry → code + new password. Presented as `.medium/.large` sheet over
`SignInView`.

---

## Face ID enrollment

Offered once, after the first successful sign-in on a Face ID–capable device.

**Trigger:** `session.state` transitions to `.ready` AND `BiometricAuth.isAvailable == true` AND
`faceIDEnabled == false`

**UI:** `EnableBiometricSheet` — `.medium` sheet presented over `mainStack` (not over the auth
flow). Shows the Face ID icon, a title, and two options: "Enable Face ID" and "Not now."

**On enable:** `auth.enableBiometrics()` saves the current `email`/`password` to Keychain, then
`faceIDEnabled = true` is set in `@AppStorage`.

**On dismiss without enabling:** `faceIDEnabled` stays `false`. Sheet is not offered again in the
same session (only triggers once per `.ready` transition).

---

## Keychain & credential lifecycle

- Credentials (email + password) saved under `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`
- Saved on: user taps "Enable Face ID" in `EnableBiometricSheet`
- Deleted on: user explicitly disables Face ID (future settings screen)
- `faceIDEnabled` (`@AppStorage`) is the gate; Keychain is the store
- If Keychain read returns nil but `faceIDEnabled == true` (e.g., app re-install): silently fall
  through to the normal sign-in buttons — no error shown

---

## Session state additions

`Session` needs to expose why it is signed out so `AuthLandingView` can decide whether to
auto-attempt Face ID:

```swift
// New property on Session
private(set) var signedOutExplicitly = false
```

- Set to `true` only in `signOut()` (explicit user action)
- Set to `false` when `refresh()` succeeds (`.ready` / `.onboarding`)
- Never set by `refresh()` failure — expiry leaves it as whatever it was before

`AuthLandingView` receives or reads `session.signedOutExplicitly` and skips the Face ID
auto-attempt if `true`.

---

## RootView routing

```
session.state
├── .checking    → LoadingView
├── .signedOut   → authFlow (always lands on .landing)
├── .onboarding  → CreateGroupView
└── .ready       → mainStack + EnableBiometricSheet (if unenrolled)

authScreen (sub-state, only active while .signedOut)
├── .landing  → AuthLandingView
├── .signIn   → SignInView
└── .signUp   → SignUpView
```

`BiometricLockView` is removed — the landing page absorbs its role.

On sign-out: `authScreen` resets to `.landing`. The landing page's `onAppear` auto-attempt
checks `signedOutExplicitly` and skips.

---

## What changes from the current implementation

| Area                        | Current                                         | After                                                       |
| --------------------------- | ----------------------------------------------- | ----------------------------------------------------------- |
| `BiometricLockView.swift`   | Separate lock screen, shown instead of landing  | Deleted                                                     |
| `AuthScreen` enum           | `.landing / .signIn / .signUp / .biometricLock` | `.landing / .signIn / .signUp`                              |
| `AuthLandingView`           | Buttons only                                    | Buttons + silent Face ID attempt on appear                  |
| `Session`                   | No sign-out reason                              | `signedOutExplicitly: Bool` property                        |
| `RootView` onChange         | Routes to `.biometricLock` if enrolled          | Always routes to `.landing`                                 |
| `SignInView` Face ID button | Calls `signInWithBiometrics()` directly         | Calls `BiometricAuth.authenticate()` first ✓ (already done) |
