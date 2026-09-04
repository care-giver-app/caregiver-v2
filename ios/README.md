# Caregiver iOS

Native SwiftUI client (iOS 17+) for Caregiver v2. Generated from `project.yml` via **XcodeGen** —
the `.xcodeproj` is gitignored, so you regenerate it locally rather than pulling it from git.

## Prerequisites

- **Xcode 26+** (Xcode 26.2 / Swift 6 toolchain is what CI and local dev currently use)
- **XcodeGen**: `brew install xcodegen`
- An **iPhone 17 simulator** installed (Xcode → Settings → Platforms). CI resolves the simulator
  name dynamically, but local docs/commands below assume `iPhone 17`.
- No AWS credentials needed to build/run: `Config/{Dev,Prod}.xcconfig` and
  `Caregiver/Resources/amplifyconfiguration-{dev,prod}.json` (Cognito pool IDs, not secrets) are
  checked into the repo.

## First-time setup

From the repo root (`caregiver-v2/`), after cloning:

```bash
cd ios
xcodegen generate
open Caregiver.xcodeproj
```

Then build/run the `Caregiver` scheme on an iPhone 17 simulator from Xcode as usual.

**Re-run `xcodegen generate` any time you pull changes to `project.yml`** — the generated
`.xcodeproj` is not committed, so it can drift out of sync with the source of truth otherwise.

### First build is slow

The first Swift Package resolve (Amplify, AWS Common Runtime, swift-openapi-generator, and the
generated `CaregiverAPI` client from `../shared/types-swift`) can take several minutes. Xcode
caches the result in DerivedData, so subsequent builds are fast.

## Building & testing from the CLI

```bash
cd ios
xcodegen generate
xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

`-skipPackagePluginValidation` is **required** on every `xcodebuild` invocation — `CaregiverAPI`
generates its Swift sources at build time via the swift-openapi-generator build-tool plugin, and
`xcodebuild` refuses to run that plugin non-interactively without this flag.

If the simulator throws a transient "Application failed preflight checks / Busy" error on test
launch, pre-boot a device and target it by UDID instead of relying on `-destination name:...`:

```bash
UDID=$(xcrun simctl list devices available | grep 'iPhone 17 (' | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcodebuild test -scheme Caregiver -destination "platform=iOS Simulator,id=$UDID" \
  -skipPackagePluginValidation
```

## Config & environments

- `Config/Dev.xcconfig` / `Config/Prod.xcconfig` set `API_BASE_URL`, wired through
  `Caregiver/Resources/Info.plist` into the app bundle. Debug builds use Dev, Release builds use
  Prod (see `configFiles` in `project.yml`).
- `Caregiver/Resources/amplifyconfiguration-{dev,prod}.json` configure Amplify/Cognito (auth). The
  app picks the dev or prod file per build configuration.
- The API client sends the Cognito **ID token** (not the access token) — the access token doesn't
  carry `email`/`name`.

## Running against prod on your own device

A **Release** build _is_ the prod app: `project.yml` maps `Release → Config/Prod.xcconfig`
(`https://api-v2.caretosher.com`), and the app's single `#if DEBUG` in `CaregiverApp.swift` selects
`amplifyconfiguration-prod.json` in non-DEBUG builds. There is no separate prod scheme to switch to.

```bash
cd ios && xcodegen generate && open Caregiver.xcodeproj
```

Then, once per machine:

1. **Product → Scheme → Edit Scheme → Run → Build Configuration: `Release`**
2. Target `Caregiver` → **Signing & Capabilities** → tick _Automatically manage signing_ and pick
   your Apple ID team. The bundle id is `caretosher.caregiverapp.ios`.
3. Plug in the iPhone, select it as the run destination, ⌘R.

Switch the Run configuration back to `Debug` to return to the dev stage. Note that Release strips
`assertionFailure`, so an Amplify misconfiguration fails silently at sign-in rather than trapping.

## Project structure

- `Caregiver/` — app sources
- `CaregiverTests/` — unit tests (XCTest)
- `Config/` — per-environment `.xcconfig` files
- `project.yml` — XcodeGen source of truth; **never hand-edit the generated `.xcodeproj`**

## Troubleshooting

- **"Validate plug-in OpenAPIGenerator" failure**: you're missing `-skipPackagePluginValidation`
  on the `xcodebuild` invocation.
- **Simulator not found**: install an iPhone 17 simulator runtime via Xcode → Settings →
  Platforms, or substitute an installed device name in `-destination`.
- **Stale project after editing `project.yml`**: re-run `xcodegen generate` and re-open Xcode.
- **Test bundle fails to code-sign / missing bundle ID**: usually means `project.yml` regenerated
  without expected Info.plist keys — diff against git before debugging further, since the app
  target has `GENERATE_INFOPLIST_FILE: NO` and relies on `Caregiver/Resources/Info.plist`.
