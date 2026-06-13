# C1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the iOS app's foundation — an XcodeGen project that builds & tests in CI, the `Theme` design system, the networking/auth spine, and Cognito sign-up/in/out via Amplify — producing a runnable app that authenticates against dev and lands on an (empty) dashboard.

**Architecture:** Native SwiftUI (iOS 17+), plain `@Observable` state. A single `Session` injected via `@Environment` owns Amplify auth state + a configured `CaregiverAPI.Client` (generated in B3a) + the bootstrapped `Me`. An auth middleware stamps the Cognito **ID token** on every request. The Xcode project is generated from `ios/project.yml` (XcodeGen).

**Tech Stack:** Swift 6.2 / Xcode 26.2, SwiftUI, XcodeGen, Amplify Swift (Auth), `swift-openapi` runtime/URLSession, the local `CaregiverAPI` SwiftPM package.

**Source spec:** `docs/specs/2026-06-12-c1-ios-mvp-design.md` (this plan is **Stage 1 of 2** — Foundation; the Features plan follows once this lands).

**Conventions (from `CLAUDE.md`):** Conventional Commits, lowercase subject. Branch is `c1-ios-mvp` (already created off `main`). Do **not** merge; open a PR at the end. The repo is public, so the macOS CI job is free.

**⚠️ Toolchain-verification rule (read once):** This plan's Amplify / swift-openapi / XcodeGen snippets are written to the APIs as of authoring. The exact signatures **must be verified against the installed package versions**. Every task that touches a third-party API ends with a **compile step**; if the compiler disagrees with a snippet, **adapt the call to the installed API** (check the package's headers via Xcode "Jump to Definition" or the resolved source in `~/Library/Developer/Xcode/DerivedData` / `.build`), keep the **behavior** identical, and note the adaptation in the commit body. Do not weaken a test to dodge an API mismatch.

---

## File structure (Foundation)

```
ios/
  .gitignore                     # *.xcodeproj/, DerivedData/, build artifacts
  project.yml                    # XcodeGen spec — source of truth
  Config/
    Dev.xcconfig                 # API_BASE_URL for dev
    Prod.xcconfig                # API_BASE_URL for prod
  Caregiver/
    App/
      CaregiverApp.swift         # @main entry, Amplify config, Session in @Environment
      RootView.swift             # switches on Session state
    Auth/
      AuthModel.swift            # @Observable: sign up/confirm/in/out via Amplify
      SignInView.swift
      SignUpView.swift
      ConfirmCodeView.swift
    Onboarding/
      OnboardingPlaceholderView.swift   # Foundation stub (real create-group is Plan 2)
    Dashboard/
      DashboardPlaceholderView.swift    # Foundation stub (real dashboard is Plan 2)
    DesignSystem/
      Color+Hex.swift            # hex string -> Color
      Theme.swift                # semantic tokens (colors/spacing/radius/typography)
      Components.swift           # PrimaryButton, SecondaryButton, state views
    Support/
      AppConfig.swift            # reads API_BASE_URL from Info.plist
      AuthMiddleware.swift       # ClientMiddleware: stamps bearer from a TokenProvider
      APIClient.swift            # builds CaregiverAPI.Client (transport + middleware)
      AppError.swift             # friendly error + mapping
      CognitoTokenProvider.swift # Amplify fetchAuthSession -> ID token
      Session.swift              # @Observable session state machine + /me bootstrap
    Resources/
      Info.plist
      amplifyconfiguration-dev.json
      amplifyconfiguration-prod.json
  CaregiverTests/
    ColorHexTests.swift
    AuthMiddlewareTests.swift
    AppErrorTests.swift
    SessionTests.swift
```

---

## Section A — Project scaffold + CI (prove the toolchain)

**Section gate (AC):**

- `cd ios && xcodegen generate` produces `Caregiver.xcodeproj` (gitignored).
- `xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build` succeeds (app + deps resolve: CaregiverAPI + Amplify).
- `xcodebuild test` runs a trivial unit test green on the simulator.
- A path-gated macOS CI job builds + tests on PRs touching `ios/**` or `shared/types-swift/**`.

---

### Task A1: XcodeGen project + app shell that builds

**Files:**

- Create: `ios/.gitignore`, `ios/project.yml`, `ios/Config/Dev.xcconfig`, `ios/Config/Prod.xcconfig`
- Create: `ios/Caregiver/App/CaregiverApp.swift`, `ios/Caregiver/Dashboard/DashboardPlaceholderView.swift`
- Create: `ios/Caregiver/Resources/Info.plist`

- [ ] **Step 1: Install XcodeGen if missing**

Run: `which xcodegen || brew install xcodegen`
Expected: a path to `xcodegen` (install if absent).

- [ ] **Step 2: Create `ios/.gitignore`**

```gitignore
# Generated Xcode project
*.xcodeproj/
# Build output
DerivedData/
build/
.build/
*.xcuserstate
```

- [ ] **Step 3: Create `ios/Config/Dev.xcconfig` and `ios/Config/Prod.xcconfig`**

`ios/Config/Dev.xcconfig` — replace the URL with the dev HTTP API URL from the CDK output `HttpApiUrl` (see `docs/runbook.md`); the placeholder host below is fine until wired:

```
// Trailing slash omitted intentionally.
API_BASE_URL = https:/$()/api.dev.example.com
```

`ios/Config/Prod.xcconfig`:

```
API_BASE_URL = https:/$()/api.example.com
```

(The `/$()/` trick escapes the `//` so xcconfig doesn't treat it as a comment.)

- [ ] **Step 4: Create `ios/Caregiver/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Caregiver</string>
  <key>UILaunchScreen</key>
  <dict/>
  <key>API_BASE_URL</key>
  <string>$(API_BASE_URL)</string>
</dict>
</plist>
```

- [ ] **Step 5: Create `ios/project.yml`**

```yaml
name: Caregiver
options:
  bundleIdPrefix: app.caregiver
  deploymentTarget:
    iOS: '17.0'
  developmentLanguage: en
configs:
  Debug: debug
  Release: release
settingGroups:
  base:
    SWIFT_VERSION: '6.0'
    TARGETED_DEVICE_FAMILY: '1' # iPhone
    GENERATE_INFOPLIST_FILE: NO
packages:
  CaregiverAPI:
    path: ../shared/types-swift
  Amplify:
    url: https://github.com/aws-amplify/amplify-swift
    from: '2.39.0'
targets:
  Caregiver:
    type: application
    platform: iOS
    sources:
      - Caregiver
    configFiles:
      Debug: Config/Dev.xcconfig
      Release: Config/Prod.xcconfig
    settings:
      groups: [base]
      base:
        INFOPLIST_FILE: Caregiver/Resources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: app.caregiver.ios
    dependencies:
      - package: CaregiverAPI
        product: CaregiverAPI
      - package: Amplify
        product: Amplify
      - package: Amplify
        product: AWSCognitoAuthPlugin
  CaregiverTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - CaregiverTests
    dependencies:
      - target: Caregiver
    settings:
      groups: [base]
```

- [ ] **Step 6: Create the minimal app + a placeholder dashboard so it compiles & runs**

`ios/Caregiver/App/CaregiverApp.swift`:

```swift
import SwiftUI

@main
struct CaregiverApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardPlaceholderView()
        }
    }
}
```

`ios/Caregiver/Dashboard/DashboardPlaceholderView.swift`:

```swift
import SwiftUI

struct DashboardPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Caregiver")
                .font(.largeTitle.bold())
            Text("Foundation shell")
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 7: Generate and build**

Run:

```bash
cd ios && xcodegen generate
xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. (Amplify + CaregiverAPI packages resolve on first build — this can take several minutes. If the simulator name `iPhone 16` is unavailable, run `xcrun simctl list devices available` and use an available iPhone.)

If the build fails on a package/product name (e.g. Amplify product naming changed), verify the available products with `xcodebuild -list` after `xcodegen generate`, or inspect `https://github.com/aws-amplify/amplify-swift` `Package.swift`, and correct `project.yml`. Keep `Amplify` + `AWSCognitoAuthPlugin` as the intended products.

- [ ] **Step 8: Commit**

```bash
cd /Users/trevorwilliams/Code/CareGiverApp/caregiver-v2
git add ios/.gitignore ios/project.yml ios/Config ios/Caregiver/App ios/Caregiver/Dashboard/DashboardPlaceholderView.swift ios/Caregiver/Resources/Info.plist
git commit -m "feat: xcodegen ios app shell that builds"
```

---

### Task A2: Unit-test target runs green on the simulator

**Files:**

- Create: `ios/CaregiverTests/SmokeTests.swift`

- [ ] **Step 1: Write a trivial failing test**

```swift
import XCTest
@testable import Caregiver

final class SmokeTests: XCTestCase {
    func testTrue() {
        XCTAssertEqual(2 + 2, 5) // intentionally wrong to confirm the harness runs
    }
}
```

- [ ] **Step 2: Regenerate + run tests, confirm it FAILS**

Run:

```bash
cd ios && xcodegen generate
xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -25
```

Expected: test FAILS (`XCTAssertEqual failed: 4 != 5`) — proving the test harness executes.

- [ ] **Step 3: Fix the assertion**

```swift
import XCTest
@testable import Caregiver

final class SmokeTests: XCTestCase {
    func testTrue() {
        XCTAssertEqual(2 + 2, 4)
    }
}
```

- [ ] **Step 4: Run tests, confirm PASS**

Run: `cd ios && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/CaregiverTests/SmokeTests.swift
git commit -m "test: ios unit-test target runs on simulator"
```

---

### Task A3: macOS CI job (path-gated)

**Files:**

- Modify: `.github/workflows/ci-pr.yml`

- [ ] **Step 1: Inspect the current workflow** to match its style.

Run: `sed -n '1,40p' .github/workflows/ci-pr.yml`
Expected: see the existing `on:`/`jobs:` structure.

- [ ] **Step 2: Add an `ios` job** to `.github/workflows/ci-pr.yml` under `jobs:` (a macOS runner, gated to iOS-relevant paths via a `paths-filter` step so it self-skips on backend-only PRs):

```yaml
ios:
  name: iOS build + test
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - uses: dorny/paths-filter@v3
      id: changes
      with:
        filters: |
          ios:
            - 'ios/**'
            - 'shared/types-swift/**'
            - 'shared/openapi/openapi.yaml'
    - name: Install XcodeGen
      if: steps.changes.outputs.ios == 'true'
      run: brew install xcodegen
    - name: Generate project
      if: steps.changes.outputs.ios == 'true'
      run: cd ios && xcodegen generate
    - name: Build + test
      if: steps.changes.outputs.ios == 'true'
      run: |
        cd ios
        xcodebuild test \
          -scheme Caregiver \
          -destination 'platform=iOS Simulator,name=iPhone 16' \
          -resultBundlePath TestResults \
          CODE_SIGNING_ALLOWED=NO | xcpretty || exit ${PIPESTATUS[0]}
```

If `xcpretty` is unavailable on the runner image, drop the `| xcpretty …` pipe and run `xcodebuild test …` directly. Verify the runner's available simulators in the logs and adjust the device name if `iPhone 16` is absent.

- [ ] **Step 3: Validate the YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci-pr.yml')); print('yaml ok')"`
Expected: `yaml ok`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci-pr.yml
git commit -m "ci: path-gated macos ios build + test job"
```

---

## Section B — Design system (Theme tokens + components)

**Section gate (AC):**

- `Color(hex:)` parses `#RRGGBB` / `RRGGBB` (and returns a sensible fallback for bad input); unit-tested.
- `Theme` exposes semantic color/spacing/radius/typography tokens; **no component hard-codes a hex or magic number**.
- Reusable components (`PrimaryButton`, `SecondaryButton`, `LoadingView`, `EmptyStateView`, `ErrorStateView`) compile and reference only `Theme`.

---

### Task B1: hex → Color (with tests)

**Files:**

- Create: `ios/Caregiver/DesignSystem/Color+Hex.swift`
- Create: `ios/CaregiverTests/ColorHexTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Caregiver

final class ColorHexTests: XCTestCase {
    func testParsesSixDigitHexWithHash() {
        let c = Color(hex: "#1F6FEB")
        XCTAssertNotNil(c.rgbaComponents)
        let rgba = c.rgbaComponents!
        XCTAssertEqual(rgba.r, 0x1F / 255.0, accuracy: 0.01)
        XCTAssertEqual(rgba.g, 0x6F / 255.0, accuracy: 0.01)
        XCTAssertEqual(rgba.b, 0xEB / 255.0, accuracy: 0.01)
    }

    func testParsesWithoutHash() {
        XCTAssertNotNil(Color(hex: "30A46C").rgbaComponents)
    }

    func testBadInputFallsBackToGray() {
        let c = Color(hex: "not-a-color")
        XCTAssertNotNil(c.rgbaComponents) // fallback, not a crash
    }
}
```

- [ ] **Step 2: Run it, confirm it FAILS**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/ColorHexTests 2>&1 | tail -20`
Expected: FAIL — `Color(hex:)` / `rgbaComponents` undefined.

- [ ] **Step 3: Implement**

```swift
import SwiftUI
import UIKit

extension Color {
    /// Parses "#RRGGBB" or "RRGGBB". Falls back to system gray on bad input so a
    /// malformed tracker color never crashes the UI.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = Color(.systemGray)
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// Test-only accessor for the resolved RGBA components.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
```

- [ ] **Step 4: Run it, confirm PASS**

Run: `cd ios && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/ColorHexTests 2>&1 | tail -10`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/DesignSystem/Color+Hex.swift ios/CaregiverTests/ColorHexTests.swift
git commit -m "feat: hex-to-color parsing for tracker colors"
```

---

### Task B2: Theme tokens

**Files:**

- Create: `ios/Caregiver/DesignSystem/Theme.swift`

- [ ] **Step 1: Implement the token system**

Code-based semantic tokens using dynamic colors (light value now; the dynamic `UIColor` closure leaves room for a dark value later with zero component changes — satisfying the spec's "dark-ready, components reference tokens only" intent without an asset catalog):

```swift
import SwiftUI
import UIKit

enum Theme {
    enum Colors {
        static let accent = dynamic(light: "1F6FEB")
        static let textPrimary = dynamic(light: "16324F")
        static let textSecondary = dynamic(light: "5B7088")
        static let textTertiary = dynamic(light: "9AA7B5")
        static let surface = dynamic(light: "FFFFFF")
        static let background = dynamic(light: "F4F6F8")
        static let border = dynamic(light: "E6EAEF")
        static let alert = dynamic(light: "E5484D")   // reserved: C2 breach badge
        static let success = dynamic(light: "30A46C")

        /// A dynamic color. `dark` defaults to `light` until a dark theme is designed;
        /// because everything references these tokens, adding dark values is additive.
        private static func dynamic(light: String, dark: String? = nil) -> Color {
            Color(UIColor { traits in
                let hex = (traits.userInterfaceStyle == .dark ? (dark ?? light) : light)
                return UIColor(Color(hex: hex))
            })
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 11
    }

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 20, weight: .semibold)
        static let headline = Font.system(size: 16, weight: .semibold)
        static let body = Font.system(size: 15, weight: .regular)
        static let subhead = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
    }
}
```

- [ ] **Step 2: Compile**

Run: `cd ios && xcodegen generate && xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -8`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/Caregiver/DesignSystem/Theme.swift
git commit -m "feat: theme design tokens"
```

---

### Task B3: Reusable components

**Files:**

- Create: `ios/Caregiver/DesignSystem/Components.swift`

- [ ] **Step 1: Implement the shared components** (each references only `Theme`):

```swift
import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else { Text(title).font(Theme.Typography.headline) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md - 2)
            .foregroundStyle(.white)
            .background(Theme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .disabled(isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md - 3)
                .foregroundStyle(Theme.Colors.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(Theme.Colors.accent, lineWidth: 1.5)
                )
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            SecondaryButton(title: "Try again", action: retry)
                .frame(maxWidth: 200)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Compile**

Run: `cd ios && xcodegen generate && xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -8`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/Caregiver/DesignSystem/Components.swift
git commit -m "feat: reusable design-system components"
```

---

## Section C — Networking & auth spine

**Section gate (AC):**

- `AppConfig.baseURL` reads `API_BASE_URL` from the Info.plist.
- `AuthMiddleware` sets `Authorization: Bearer <token>` from an injected `TokenProvider`; unit-tested with a fake provider (and the no-token case).
- `AppError` maps transport failures + non-success responses to friendly messages; unit-tested.
- `APIClient` builds a `CaregiverAPI.Client` from base URL + transport + the auth middleware (compiles).
- Amplify configures at launch; `CognitoTokenProvider` returns the **ID token** via `fetchAuthSession`.
- `AuthModel` drives sign up → confirm → sign in → sign out (compiles; screens render).
- `Session` is a state machine (`.checking/.signedOut/.onboarding/.ready`) with `/me` bootstrap; transitions unit-tested with fakes.

---

### Task C1: AppConfig + API client factory

**Files:**

- Create: `ios/Caregiver/Support/AppConfig.swift`
- Create: `ios/Caregiver/Support/APIClient.swift`

- [ ] **Step 1: Implement `AppConfig`**

```swift
import Foundation

enum AppConfig {
    /// The API base URL, injected from the active .xcconfig via Info.plist.
    static var baseURL: URL {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: s) else {
            preconditionFailure("API_BASE_URL missing/invalid in Info.plist")
        }
        return url
    }
}
```

- [ ] **Step 2: Implement `APIClient`** — builds the generated client with the auth middleware.

> Verify against the installed `CaregiverAPI`/`OpenAPIURLSession` API: the generated `Client` initializer is `Client(serverURL:transport:middlewares:)` per the B3a smoke test pattern. `AuthMiddleware` is defined in Task C2 — this file depends on it, so implement C2 first or in the same change; the plan orders the test for C2 next.

```swift
import Foundation
import CaregiverAPI
import OpenAPIURLSession

enum APIClient {
    /// Builds a CaregiverAPI client pointed at the configured base URL, with the
    /// auth middleware that stamps the bearer token on every request.
    static func make(tokenProvider: TokenProvider) -> Client {
        Client(
            serverURL: AppConfig.baseURL,
            transport: URLSessionTransport(),
            middlewares: [AuthMiddleware(tokenProvider: tokenProvider)]
        )
    }
}
```

- [ ] **Step 3: Commit** (after C2 compiles — these two land together)

```bash
git add ios/Caregiver/Support/AppConfig.swift ios/Caregiver/Support/APIClient.swift
git commit -m "feat: app config and api client factory"
```

---

### Task C2: Auth middleware (with tests)

**Files:**

- Create: `ios/Caregiver/Support/AuthMiddleware.swift`
- Create: `ios/CaregiverTests/AuthMiddlewareTests.swift`

- [ ] **Step 1: Write the failing test** — a fake token provider + a captured request prove the header is set.

> Verify the `ClientMiddleware` protocol signature against the installed `OpenAPIRuntime` (it uses `HTTPRequest`/`HTTPBody` from swift-http-types). If the `intercept` signature differs, adapt both the implementation and this test's `next` closure to match — the assertion (bearer header present) stays.

```swift
import XCTest
import HTTPTypes
import OpenAPIRuntime
@testable import Caregiver

private struct FakeTokenProvider: TokenProvider {
    let token: String?
    func idToken() async throws -> String? { token }
}

final class AuthMiddlewareTests: XCTestCase {
    func testStampsBearerWhenTokenPresent() async throws {
        let mw = AuthMiddleware(tokenProvider: FakeTokenProvider(token: "abc.def.ghi"))
        var seen: HTTPRequest?
        let req = HTTPRequest(method: .get, scheme: "https", authority: "x", path: "/me")
        _ = try await mw.intercept(req, body: nil, baseURL: URL(string: "https://x")!, operationID: "getMe") { r, b, _ in
            seen = r
            return (HTTPResponse(status: .ok), nil)
        }
        XCTAssertEqual(seen?.headerFields[.authorization], "Bearer abc.def.ghi")
    }

    func testNoHeaderWhenTokenNil() async throws {
        let mw = AuthMiddleware(tokenProvider: FakeTokenProvider(token: nil))
        var seen: HTTPRequest?
        let req = HTTPRequest(method: .get, scheme: "https", authority: "x", path: "/me")
        _ = try await mw.intercept(req, body: nil, baseURL: URL(string: "https://x")!, operationID: "getMe") { r, b, _ in
            seen = r
            return (HTTPResponse(status: .ok), nil)
        }
        XCTAssertNil(seen?.headerFields[.authorization])
    }
}
```

- [ ] **Step 2: Run it, confirm it FAILS** (undefined `TokenProvider`/`AuthMiddleware`).

Run: `cd ios && xcodegen generate && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/AuthMiddlewareTests 2>&1 | tail -25`
Expected: FAIL (compile / undefined symbols).

- [ ] **Step 3: Implement**

```swift
import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Supplies the current Cognito ID token (nil when signed out).
protocol TokenProvider: Sendable {
    func idToken() async throws -> String?
}

/// Stamps `Authorization: Bearer <id-token>` on every outgoing request.
struct AuthMiddleware: ClientMiddleware {
    let tokenProvider: TokenProvider

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = try await tokenProvider.idToken() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}
```

- [ ] **Step 4: Run it, confirm PASS**

Run: `cd ios && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/AuthMiddlewareTests 2>&1 | tail -10`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit** (with the C1 files that depend on it)

```bash
git add ios/Caregiver/Support/AuthMiddleware.swift ios/CaregiverTests/AuthMiddlewareTests.swift ios/Caregiver/Support/AppConfig.swift ios/Caregiver/Support/APIClient.swift
git commit -m "feat: auth middleware stamping the cognito id token"
```

---

### Task C3: AppError mapping (with tests)

**Files:**

- Create: `ios/Caregiver/Support/AppError.swift`
- Create: `ios/CaregiverTests/AppErrorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Caregiver

final class AppErrorTests: XCTestCase {
    func testForbiddenMessage() {
        XCTAssertEqual(AppError.forStatus(403, serverMessage: nil).message,
                       "You don't have permission to do that.")
    }

    func testBadRequestSurfacesServerMessage() {
        XCTAssertEqual(AppError.forStatus(400, serverMessage: "systolic is required").message,
                       "systolic is required")
    }

    func testNotFoundMessage() {
        XCTAssertEqual(AppError.forStatus(404, serverMessage: nil).message, "Not found.")
    }

    func testTransportMessage() {
        XCTAssertEqual(AppError.transport.message, "No connection — please try again.")
    }
}
```

- [ ] **Step 2: Run it, confirm FAIL.**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/AppErrorTests 2>&1 | tail -20`
Expected: FAIL (undefined `AppError`).

- [ ] **Step 3: Implement**

```swift
import Foundation

/// A user-facing error with a friendly message.
struct AppError: Error, Equatable {
    let message: String

    static let transport = AppError(message: "No connection — please try again.")
    static let unknown = AppError(message: "Something went wrong. Please try again.")

    static func forStatus(_ status: Int, serverMessage: String?) -> AppError {
        switch status {
        case 400: return AppError(message: serverMessage ?? "That didn't look right.")
        case 401: return AppError(message: "Your session expired. Please sign in again.")
        case 403: return AppError(message: "You don't have permission to do that.")
        case 404: return AppError(message: "Not found.")
        default:  return serverMessage.map { AppError(message: $0) } ?? .unknown
        }
    }
}
```

- [ ] **Step 4: Run it, confirm PASS.**

Run: `cd ios && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/AppErrorTests 2>&1 | tail -10`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Support/AppError.swift ios/CaregiverTests/AppErrorTests.swift
git commit -m "feat: friendly app error mapping"
```

---

### Task C4: Amplify config + Cognito token provider

**Files:**

- Create: `ios/Caregiver/Resources/amplifyconfiguration-dev.json`, `amplifyconfiguration-prod.json`
- Create: `ios/Caregiver/Support/CognitoTokenProvider.swift`
- Modify: `ios/project.yml` (ensure `Resources/` is bundled), `ios/Caregiver/App/CaregiverApp.swift` (configure Amplify; pick the per-stage config)

- [ ] **Step 1: Create the Amplify config files.** Fill `PoolId`/`AppClientId`/`Region` from the CDK outputs (`UserPoolId`, `UserPoolClientId`; region `us-east-2`) — see `docs/runbook.md`. Dev:

```json
{
  "auth": {
    "plugins": {
      "awsCognitoAuthPlugin": {
        "IdentityManager": { "Default": {} },
        "CognitoUserPool": {
          "Default": {
            "PoolId": "us-east-2_REPLACE_DEV",
            "AppClientId": "REPLACE_DEV_CLIENT_ID",
            "Region": "us-east-2"
          }
        },
        "Auth": {
          "Default": { "authenticationFlowType": "USER_SRP_AUTH" }
        }
      }
    }
  }
}
```

Create `amplifyconfiguration-prod.json` with the prod pool/client ids.

> The exact JSON shape Amplify v2 expects must match the installed plugin. If `Amplify.configure()` rejects this file, generate a reference shape from the Amplify docs for the installed version and fill in the same three values.

- [ ] **Step 2: Bundle resources** — in `project.yml`, add the resources to the `Caregiver` target sources (XcodeGen includes folder resources automatically when listed; ensure `Caregiver/Resources` is covered by `sources: [Caregiver]` — it is, since it's under `Caregiver/`). At build, the active config is chosen at runtime by build flag (Step 3). No project.yml change needed beyond what A1 set; confirm the JSONs are copied by checking the built app bundle, or add an explicit resource entry if needed.

- [ ] **Step 3: Configure Amplify at launch** — update `CaregiverApp.swift`:

```swift
import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct CaregiverApp: App {
    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            DashboardPlaceholderView() // replaced by RootView in Task C6/Section D
        }
    }

    private func configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            #if DEBUG
            let configName = "amplifyconfiguration-dev"
            #else
            let configName = "amplifyconfiguration-prod"
            #endif
            guard let url = Bundle.main.url(forResource: configName, withExtension: "json") else {
                preconditionFailure("\(configName).json missing from bundle")
            }
            let config = try AmplifyConfiguration(configurationFile: url)
            try Amplify.configure(config)
        } catch {
            // In DEBUG, fail loudly so misconfig is caught early.
            assertionFailure("Amplify configure failed: \(error)")
        }
    }
}
```

> Verify `AmplifyConfiguration(configurationFile:)` exists in the installed Amplify; if the v2 API differs (e.g. expects a bundled `amplifyconfiguration.json` by name via `Amplify.configure()`), adapt: name the active file `amplifyconfiguration.json` per-config via build phase, or use the installed configuration entry point. Keep "DEBUG→dev, RELEASE→prod" behavior.

- [ ] **Step 4: Implement the token provider**

```swift
import Foundation
import Amplify

/// Pulls the current Cognito ID token from Amplify for the auth middleware.
struct CognitoTokenProvider: TokenProvider {
    func idToken() async throws -> String? {
        let session = try await Amplify.Auth.fetchAuthSession()
        guard let provider = session as? AuthCognitoTokensProvider else { return nil }
        switch provider.getCognitoTokens() {
        case .success(let tokens): return tokens.idToken
        case .failure: return nil
        }
    }
}
```

> Verify `AuthCognitoTokensProvider` / `getCognitoTokens()` / `tokens.idToken` against the installed AWSCognitoAuthPlugin. Adapt names if the API differs; the behavior (return the ID token, or nil when signed out) is the contract.

- [ ] **Step 5: Build**

Run: `cd ios && xcodegen generate && xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -12`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add ios/Caregiver/Resources/amplifyconfiguration-dev.json ios/Caregiver/Resources/amplifyconfiguration-prod.json ios/Caregiver/Support/CognitoTokenProvider.swift ios/Caregiver/App/CaregiverApp.swift ios/project.yml
git commit -m "feat: amplify configuration and cognito token provider"
```

---

### Task C5: Auth model + screens

**Files:**

- Create: `ios/Caregiver/Auth/AuthModel.swift`, `SignInView.swift`, `SignUpView.swift`, `ConfirmCodeView.swift`

- [ ] **Step 1: Implement `AuthModel`** (an `@Observable` wrapping Amplify auth calls; surfaces errors as `AppError`):

```swift
import Foundation
import Amplify

@Observable
final class AuthModel {
    var email = ""
    var password = ""
    var code = ""
    var isBusy = false
    var error: AppError?
    var needsConfirmation = false

    /// Called by the owner (Session) after a successful sign-in to re-bootstrap.
    var onSignedIn: () async -> Void = {}

    func signUp() async {
        await run {
            let attrs = [AuthUserAttribute(.email, value: email)]
            let result = try await Amplify.Auth.signUp(
                username: email, password: password,
                options: .init(userAttributes: attrs)
            )
            if case .confirmUser = result.nextStep { needsConfirmation = true }
            else { await signIn() }
        }
    }

    func confirm() async {
        await run {
            _ = try await Amplify.Auth.confirmSignUp(for: email, confirmationCode: code)
            needsConfirmation = false
            await signIn()
        }
    }

    func signIn() async {
        await run {
            let result = try await Amplify.Auth.signIn(username: email, password: password)
            if result.isSignedIn { await onSignedIn() }
            else if case .confirmSignUp = result.nextStep { needsConfirmation = true }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true; error = nil
        do { try await work() }
        catch { self.error = AppError(message: friendly(error)) }
        isBusy = false
    }

    private func friendly(_ error: Error) -> String {
        // Amplify surfaces AuthError; show its recovery-friendly description.
        if let authError = error as? AuthError { return authError.errorDescription }
        return AppError.unknown.message
    }
}
```

> Verify `signUp`/`confirmSignUp`/`signIn` signatures + `nextStep` cases + `AuthError.errorDescription` against the installed Amplify. Adapt names if needed; keep the flow (signUp→confirm→signIn→onSignedIn) and error surfacing.

- [ ] **Step 2: Implement the three screens** (custom UI; reference `Theme`):

`SignInView.swift`:

```swift
import SwiftUI

struct SignInView: View {
    @Bindable var model: AuthModel
    var onSwitchToSignUp: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Sign in").font(Theme.Typography.largeTitle)
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $model.password)
                .textContentType(.password)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Sign in", isLoading: model.isBusy) {
                Task { await model.signIn() }
            }
            Button("Create an account", action: onSwitchToSignUp)
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.accent)
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(Theme.Spacing.lg)
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
    }
}
```

`SignUpView.swift`:

```swift
import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthModel
    var onSwitchToSignIn: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Create account").font(Theme.Typography.largeTitle)
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password (8+ chars)", text: $model.password)
                .textContentType(.newPassword)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Sign up", isLoading: model.isBusy) {
                Task { await model.signUp() }
            }
            Button("I already have an account", action: onSwitchToSignIn)
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.accent)
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(Theme.Spacing.lg)
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
    }
}
```

`ConfirmCodeView.swift`:

```swift
import SwiftUI

struct ConfirmCodeView: View {
    @Bindable var model: AuthModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Enter the code").font(Theme.Typography.title)
            Text("We emailed a confirmation code to \(model.email).")
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            TextField("Code", text: $model.code).keyboardType(.numberPad)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Confirm", isLoading: model.isBusy) {
                Task { await model.confirm() }
            }
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(Theme.Spacing.lg)
    }
}
```

- [ ] **Step 3: Build**

Run: `cd ios && xcodegen generate && xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/Caregiver/Auth
git commit -m "feat: auth model and sign-in/up/confirm screens"
```

---

### Task C6: Session state machine + /me bootstrap (with tests)

**Files:**

- Create: `ios/Caregiver/Support/Session.swift`
- Create: `ios/CaregiverTests/SessionTests.swift`

- [ ] **Step 1: Write the failing test** — drive the state machine with an injected bootstrap closure (no network):

```swift
import XCTest
@testable import Caregiver

final class SessionTests: XCTestCase {
    func testNoMembershipsGoesToOnboarding() async {
        let session = Session(bootstrap: { .init(userName: "Ann", memberships: []) },
                              signOutHandler: {})
        await session.refresh()
        guard case .onboarding = session.state else {
            return XCTFail("expected onboarding, got \(session.state)")
        }
    }

    func testWithMembershipsGoesToReady() async {
        let session = Session(
            bootstrap: { .init(userName: "Ann", memberships: [.init(careGroupID: "g1", name: "Home", role: "admin")]) },
            signOutHandler: {}
        )
        await session.refresh()
        guard case .ready = session.state else {
            return XCTFail("expected ready, got \(session.state)")
        }
    }

    func testBootstrapFailureGoesToSignedOut() async {
        struct Boom: Error {}
        let session = Session(bootstrap: { throw Boom() }, signOutHandler: {})
        await session.refresh()
        guard case .signedOut = session.state else {
            return XCTFail("expected signedOut, got \(session.state)")
        }
    }
}
```

- [ ] **Step 2: Run it, confirm FAIL** (undefined `Session`).

Run: `cd ios && xcodegen generate && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/SessionTests 2>&1 | tail -20`
Expected: FAIL.

- [ ] **Step 3: Implement `Session`** — note the injected `bootstrap`/`signOutHandler` keep it unit-testable; the production initializer wires Amplify + the real `/me` call.

```swift
import Foundation
import Amplify
import CaregiverAPI

/// App-side view of the current user + their care-group memberships.
struct Me: Equatable {
    struct Membership: Equatable {
        let careGroupID: String
        let name: String
        let role: String
    }
    let userName: String
    let memberships: [Membership]
}

@Observable
final class Session {
    enum State: Equatable {
        case checking
        case signedOut
        case onboarding(Me)
        case ready(Me)
    }

    private(set) var state: State = .checking

    private let bootstrap: () async throws -> Me
    private let signOutHandler: () async -> Void

    /// Testable initializer.
    init(bootstrap: @escaping () async throws -> Me,
         signOutHandler: @escaping () async -> Void) {
        self.bootstrap = bootstrap
        self.signOutHandler = signOutHandler
    }

    /// Production initializer: real Amplify sign-in check + GET /me.
    convenience init() {
        let client = APIClient.make(tokenProvider: CognitoTokenProvider())
        self.init(
            bootstrap: {
                // Only call /me when Amplify reports a signed-in session.
                let authSession = try await Amplify.Auth.fetchAuthSession()
                guard authSession.isSignedIn else { throw NotSignedIn() }
                let response = try await client.getMe()
                let me = try response.ok.body.json
                return Me(
                    userName: me.user.name,
                    memberships: me.memberships.map {
                        Me.Membership(careGroupID: $0.care_group_id, name: $0.name, role: $0.role.rawValue)
                    }
                )
            },
            signOutHandler: { _ = await Amplify.Auth.signOut() }
        )
    }

    struct NotSignedIn: Error {}

    @MainActor
    func refresh() async {
        state = .checking
        do {
            let me = try await bootstrap()
            state = me.memberships.isEmpty ? .onboarding(me) : .ready(me)
        } catch {
            state = .signedOut
        }
    }

    @MainActor
    func signOut() async {
        await signOutHandler()
        state = .signedOut
    }
}
```

> Verify the generated `getMe()` response shape (`response.ok.body.json`, and the JSON property names `user.name`, `memberships[].care_group_id/name/role`) against the generated `CaregiverAPI` (`namingStrategy: idiomatic` may camel-case these — e.g. `careGroupId`). Adapt the property accessors to the generated names; the mapping intent is unchanged.

- [ ] **Step 4: Run it, confirm PASS**

Run: `cd ios && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaregiverTests/SessionTests 2>&1 | tail -10`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Support/Session.swift ios/CaregiverTests/SessionTests.swift
git commit -m "feat: session state machine with /me bootstrap"
```

---

## Section D — Foundation wiring & verification

**Section gate (AC):**

- The app launches, shows auth when signed out, and (after sign-in) routes to the onboarding placeholder (no memberships) or the dashboard placeholder.
- Full unit suite green on the simulator; whole app builds.
- Docs note the iOS app exists; PR opened (not merged).

---

### Task D1: Root wiring (Session → screens)

**Files:**

- Create: `ios/Caregiver/App/RootView.swift`, `ios/Caregiver/Onboarding/OnboardingPlaceholderView.swift`
- Modify: `ios/Caregiver/App/CaregiverApp.swift` (host `RootView` + own the `Session`), `ios/Caregiver/Dashboard/DashboardPlaceholderView.swift` (show the signed-in user + sign-out)

- [ ] **Step 1: Implement `RootView`** — switches on `Session.state`, owns the `AuthModel`, wires `onSignedIn` → `session.refresh()`:

```swift
import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var auth = AuthModel()
    @State private var showSignUp = false

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                LoadingView()
            case .signedOut:
                authFlow
            case .onboarding(let me):
                OnboardingPlaceholderView(userName: me.userName)
            case .ready(let me):
                DashboardPlaceholderView(userName: me.userName)
            }
        }
        .task {
            auth.onSignedIn = { await session.refresh() }
            await session.refresh()
        }
    }

    @ViewBuilder private var authFlow: some View {
        if showSignUp {
            SignUpView(model: auth, onSwitchToSignIn: { showSignUp = false })
        } else {
            SignInView(model: auth, onSwitchToSignUp: { showSignUp = true })
        }
    }
}
```

- [ ] **Step 2: Implement the onboarding placeholder** (real create-group is Plan 2):

```swift
import SwiftUI

struct OnboardingPlaceholderView: View {
    let userName: String
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Welcome, \(userName)").font(Theme.Typography.title)
            Text("Next: create your care group (coming in the features build).")
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
    }
}
```

- [ ] **Step 3: Update the dashboard placeholder** to show the user + a working sign-out:

```swift
import SwiftUI

struct DashboardPlaceholderView: View {
    @Environment(Session.self) private var session
    var userName: String = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Signed in as \(userName)").font(Theme.Typography.headline)
            Text("Dashboard arrives in the features build.")
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.textSecondary)
            SecondaryButton(title: "Sign out") { Task { await session.signOut() } }
                .frame(maxWidth: 200)
        }
        .padding(Theme.Spacing.lg)
    }
}
```

- [ ] **Step 4: Host `RootView` + own the Session** in `CaregiverApp.swift` (replace the body; keep `configureAmplify()` from C4):

```swift
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView().environment(session)
        }
    }
```

- [ ] **Step 5: Build + run check**

Run: `cd ios && xcodegen generate && xcodebuild -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -8`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add ios/Caregiver/App ios/Caregiver/Onboarding ios/Caregiver/Dashboard/DashboardPlaceholderView.swift
git commit -m "feat: root view wiring session to auth/onboarding/dashboard"
```

---

### Task D2: Full verification, docs, PR

- [ ] **Step 1: Run the whole unit suite**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -15`
Expected: TEST SUCCEEDED (ColorHex, AuthMiddleware, AppError, Session, Smoke).

- [ ] **Step 2: Manual smoke (once), against dev** — fill the real dev pool/client ids + `API_BASE_URL` first (CDK outputs / runbook), then run in the simulator (Xcode ▶), and verify: sign up → receive code email → confirm → lands on onboarding placeholder; force-quit + relaunch stays signed in; sign out returns to sign-in. Note the result in the PR description. (If dev isn't wired yet, state that this manual step is deferred until the ids are filled.)

- [ ] **Step 3: Update docs** — add a short `## iOS app` note to `CLAUDE.md` (how to run: `cd ios && xcodegen generate && open Caregiver.xcodeproj`; tests via `xcodebuild test`; XcodeGen is the source of truth) and mark C1 Foundation in `docs/roadmap.md` (C1 in progress: foundation landed, features next). Format: `pnpm exec prettier --write CLAUDE.md docs/roadmap.md`. Commit:

```bash
git add CLAUDE.md docs/roadmap.md
git commit -m "docs: ios app run instructions and c1 foundation status"
```

- [ ] **Step 4: Push + open PR (do NOT merge)**

```bash
git push -u origin c1-ios-mvp
gh pr create --base main --title "feat: C1 foundation (ios app shell, design system, auth spine)" --body "$(cat <<'EOF'
Stage 1 of C1 per docs/specs/2026-06-12-c1-ios-mvp-design.md and
docs/plans/2026-06-12-c1-foundation.md.

- XcodeGen iOS app (iOS 17+) that builds + tests on a path-gated macOS CI job.
- Theme design system (semantic tokens, dark-ready) + reusable components.
- Networking/auth spine: API client factory, auth middleware (stamps the Cognito
  ID token), AppError mapping, Amplify config + token provider.
- Sign up → confirm → sign in → sign out; Session state machine + /me bootstrap
  routing to onboarding (no groups) or dashboard.

Placeholders for onboarding/dashboard; the feature screens are Stage 2.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Stop.** Do not merge — Trevor reviews (merge to `main` triggers a prod deploy via `cd-main`).

---

## Self-review notes (for the implementer)

- **Library-API risk is concentrated in Tasks C2, C4, C5, C6** (swift-openapi `ClientMiddleware`, Amplify configure/auth/token APIs, generated `getMe()` property names). Each has a compile/test gate and an explicit "adapt to the installed API" instruction. Treat a red compiler as "fix the call to match the library," not "change the design."
- **Generated property names:** `namingStrategy: idiomatic` (B3a's `oapi-config`) likely camel-cases JSON keys in Swift (`care_group_id` → `careGroupId`). Confirm against the generated `CaregiverAPI` types in Task C6 and adjust accessors.
- **Simulator name:** every `xcodebuild` step assumes `iPhone 16`. If unavailable, `xcrun simctl list devices available` and substitute; keep it consistent across tasks and the CI job.
- **Secrets:** the pool/client ids in `amplifyconfiguration-*.json` are public client identifiers (no secret), safe to commit (the app client has `generateSecret: false`). The dev/prod `API_BASE_URL` is likewise public.
- **Spec coverage (Foundation slice):** XcodeGen (A1) · macOS CI (A3) · Theme tokens + components (B) · auth middleware/ID token (C2) · AppError (C3) · Amplify (C4/C5) · Session + /me gate (C6) · root routing (D1). Deferred to the Features plan (Stage 2): receivers/trackers/events, dynamic form, history/pagination, create-group, rename/archive.
