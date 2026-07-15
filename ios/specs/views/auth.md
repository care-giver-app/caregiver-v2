# Auth flow — landing, sign in/up, confirm, reset

- **Module:** ios
- **Status:** Current — Aurora screens built (2026-07-05) from the Figma Auth Flow canvas (`18:2`).
- **Last updated:** 2026-07-05
- **Contract:** none directly — auth is **Amplify/Cognito**, not the app API. The Cognito **ID token**
  (email-as-username pool) is what `APIClient` later sends; see `Caregiver/Support/`.
- **Related specs:** [[design-system]] (StrideBrand / StrideCodeInput / StrideButton / StrideField /
  `.strideAuroraBackground()`), [[caretosher-post-login-ia]] context lives in memory; Figma file
  `qoiOteGuzktJPB6WKRbGHt`, page **Auth Flow**.

> The pre-login flow: **Landing → Sign Up → Confirm Code** (new users) and **Landing → Sign In
> (→ Forgot Password)** (returning). All five Figma frames sit on the Aurora night substrate and are
> fully component-driven; user-facing copy says **CareToSher**, never "Stride".

## Screens (Figma frame → Swift file)

| Screen          | Figma  | File                       | Notes                                                                |
| --------------- | ------ | -------------------------- | -------------------------------------------------------------------- |
| Landing         | `29:4` | `AuthLandingView.swift`    | Brand + tagline top, actions pinned bottom                           |
| Sign In         | `18:3` | `SignInView.swift`         | left-aligned heading; remember-me `.stride` toggle; Face ID optional |
| Sign Up         | `30:6` | `SignUpView.swift`         | name row (2-up fields) + email + password ×2; terms line             |
| Confirm Code    | `31:7` | `ConfirmCodeView.swift`    | **sheet**; `StrideCodeInput` + Resend row                            |
| Forgot Password | `32:8` | `ForgotPasswordView.swift` | **sheet**, two phases (email → code+new password)                    |

Shared structure: `StrideBrand` top-anchored, 24pt-medium heading (Space Grotesk in Figma; system
font stands in per the open font decision) + 14pt `textSecondary` subline, 24pt horizontal margins,
`.strideAuroraBackground()` behind everything. Scrollable screens (`SignIn`/`SignUp`) use
`.scrollBounceBehavior(.basedOnSize)`.

## Behavior (owned by `AuthModel`)

`AuthModel` (`@Observable`, Amplify calls) is unchanged in shape: `signUp` (validates password
match) → `needsConfirmation` → `confirm` → auto `signIn`; `sendResetCode`/`confirmReset` two-phase
reset; biometric credential storage in Keychain. Added 2026-07-05: **`resendCode()`**
(`Amplify.Auth.resendSignUpCode`) for the Confirm sheet's "Didn't get a code? Resend" row.

- **Navigation is a callback enum in RootView** (`landing | signIn | signUp`), not a
  NavigationStack. 2026-07-05: the screens **cross-link like the Figma flow** — Sign In has "New to
  CareToSher? → Create account", Sign Up has "Already have an account? → Sign in"; the old "Back"
  buttons to Landing are gone (Landing is a pure entry screen).
- **Remember me** (`@AppStorage`) prefills the saved email; **Face ID** button renders only when
  previously enabled (`EnableBiometricSheet`, also on the Aurora substrate — not a Figma frame).
- Error text renders inline in `alert` red below the fields — **no designed error state in Figma**
  (Bucket B, same gap as the post-login screens).

## Key decisions

| Decision                    | Choice                                                     | Why                                                                                                                               |
| --------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Confirm/Forgot presentation | **Sheets** (existing), not full-screen pushes              | Figma frames are flow frames, not presentation specs; sheets keep `needsConfirmation` auto-present from both Sign In and Sign Up. |
| Aurora glows                | Blurred gradient `Ellipse`s in `.strideAuroraBackground()` | Figma's glows are pre-blurred PNGs; drawing them ships no raster asset and stays token-tinted (approximation, tuned by eye).      |
| Reset-code entry            | `StrideCodeInput` in Forgot phase 2                        | Figma only designs phase 1; Cognito reset codes are 6-digit, so the confirm-code component fits.                                  |
| Sign In ↔ Sign Up linking   | Cross-links per Figma; "Back to landing" removed           | Matches the designed flow; Landing remains reachable only on cold start (pure entry).                                             |
| Copy case                   | Sentence case ("Sign in", "Create account")                | Figma copy; replaced the old Title Case labels.                                                                                   |

## Where it lives

| Concept               | File                                                      |
| --------------------- | --------------------------------------------------------- |
| Screens               | `ios/Caregiver/Auth/*.swift` (5 views + biometric sheet)  |
| Flow switching        | `ios/Caregiver/App/RootView.swift` (`authFlow`)           |
| Amplify calls + state | `ios/Caregiver/Auth/AuthModel.swift`                      |
| Aurora substrate      | `ios/Caregiver/DesignSystem/StrideAuroraBackground.swift` |

## Non-goals

- No social sign-in / passkeys (Cognito email+password only for C1).
- No designed error/empty states (Bucket B with the rest of the app).
- Terms/Privacy URLs still point at `caregiver.app` placeholders — swap when real pages exist.
