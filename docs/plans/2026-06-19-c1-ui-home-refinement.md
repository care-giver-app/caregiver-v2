# C1-UI Home Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tracker creation reachable from the iOS app and surface the active care team on Home, per the refinement folded into `docs/specs/2026-06-18-c1-ui-navigation-architecture.md` (Refinement 2026-06-19).

**Architecture:** Five small, independent changes to the existing SwiftUI Home/Settings surfaces. One pure-logic helper on `Me` (unit-tested TDD), three `HomeView` view changes (two-line title with team caption, team-scoped receiver dropdown with admin "Add receiver", admin "Add tracker" empty-state CTA), and one navigation change that un-orphans `ReceiverDetailView` by giving the Settings stack the same route destinations as Home and making Settings receiver rows tappable.

**Tech Stack:** SwiftUI (iOS 17+), XcodeGen (`ios/project.yml` is source of truth; `.xcodeproj` is generated), `CaregiverAPI` generated client, XCTest. Build/test runs on the iPhone 17 simulator.

---

## Preamble — branch & build sanity

The Home/Settings refinement files (`HomeView.swift`, etc.) currently live **uncommitted** on `main`.
Per `CLAUDE.md`, branch off `main` before committing; Trevor merges PRs (do not auto-merge).

- [ ] **Create a branch**

```bash
cd /Users/trevorwilliams/Code/CareGiverApp/caregiver-v2
git checkout -b c1-ui-home-refinement
```

- [ ] **Confirm the baseline builds and tests pass before changing anything**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`. If it fails, stop and fix the baseline first — do not stack new work on a red build.

> **Note on view tasks:** SwiftUI views are not unit-tested in this repo (see `ios/CaregiverTests/` — only logic is). For Tasks 2–5 the verification gate is a successful `xcodebuild test` (compiles + the existing unit suite stays green), not a new red→green test. Task 1 is pure logic and gets a real TDD cycle.

---

## File structure

| File                                        | Responsibility                               | Change                                       |
| ------------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| `ios/Caregiver/Support/Session.swift`       | `Me` model + lookups                         | **Modify** — add `teamName(forCareGroup:)`   |
| `ios/CaregiverTests/MeTeamNameTests.swift`  | Unit test for the new lookup                 | **Create**                                   |
| `ios/Caregiver/Home/HomeView.swift`         | Home screen: title, dropdown, empty state    | **Modify** — Tasks 2, 3, 4                   |
| `ios/Caregiver/App/RootView.swift`          | Tab/stack wiring + shared route destinations | **Modify** — Task 5                          |
| `ios/Caregiver/Settings/SettingsView.swift` | Settings list                                | **Modify** — Task 5 (tappable receiver rows) |

---

## Task 1: `Me.teamName(forCareGroup:)` lookup (TDD)

The team caption and team-grouped dropdown both need the care-team name for a given `care_group_id`.
This is a pure lookup over `me.memberships` — the one genuinely unit-testable unit in this refinement.

**Files:**

- Modify: `ios/Caregiver/Support/Session.swift` (the `Me` struct, near `role(inCareGroup:)`)
- Test: `ios/CaregiverTests/MeTeamNameTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/CaregiverTests/MeTeamNameTests.swift`:

```swift
import XCTest
@testable import Caregiver

final class MeTeamNameTests: XCTestCase {
    private func me(_ memberships: [Me.Membership]) -> Me {
        Me(userName: "Ann", memberships: memberships)
    }

    func testReturnsTeamNameForKnownGroup() {
        let m = me([.init(careGroupID: "g1", name: "The Williams Family", role: "admin")])
        XCTAssertEqual(m.teamName(forCareGroup: "g1"), "The Williams Family")
    }

    func testReturnsNilForUnknownGroup() {
        let m = me([.init(careGroupID: "g1", name: "The Williams Family", role: "admin")])
        XCTAssertNil(m.teamName(forCareGroup: "other"))
    }

    func testPicksCorrectTeamAmongMany() {
        let m = me([
            .init(careGroupID: "g1", name: "Home", role: "admin"),
            .init(careGroupID: "g2", name: "Mom's Team", role: "caregiver"),
        ])
        XCTAssertEqual(m.teamName(forCareGroup: "g2"), "Mom's Team")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails (compile error: no such method)**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/MeTeamNameTests
```

Expected: FAIL — `value of type 'Me' has no member 'teamName'`.

- [ ] **Step 3: Implement the lookup**

In `ios/Caregiver/Support/Session.swift`, add to `Me` directly below `func role(inCareGroup id: String)`:

```swift
    /// The care team (care-group) display name for a group id, if the user is a member.
    func teamName(forCareGroup id: String) -> String? {
        memberships.first { $0.careGroupID == id }?.name
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/MeTeamNameTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Support/Session.swift ios/CaregiverTests/MeTeamNameTests.swift ios/project.yml
git commit -m "feat(ios): add Me.teamName(forCareGroup:) lookup"
```

---

## Task 2: Home title — two-line block with care-team caption

Surface the active team under the receiver name so the user always knows who they're logging for and
which team it belongs to.

**Files:**

- Modify: `ios/Caregiver/Home/HomeView.swift` (the `.toolbar` principal item + a new computed property)

- [ ] **Step 1: Add an `activeTeamName` computed property**

In `HomeView` (after the `me` / `model` stored properties, before `var body`), add:

```swift
    private var activeTeamName: String? {
        guard let groupID = context.activeReceiver?.careGroupId else { return nil }
        return me.teamName(forCareGroup: groupID)
    }
```

- [ ] **Step 2: Replace the principal toolbar item with a two-line block**

In `body`, replace:

```swift
            ToolbarItem(placement: .principal) {
                receiverSwitcher
            }
```

with:

```swift
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    receiverSwitcher
                    if let team = activeTeamName {
                        Text(team)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                    }
                }
            }
```

- [ ] **Step 3: Build + test to verify it compiles and the suite stays green**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Caregiver/Home/HomeView.swift
git commit -m "feat(ios): show active care team under receiver name on home"
```

---

## Task 3: Receiver dropdown — scope to active team, divider for others, admin "Add receiver"

The dropdown lists the active team's receivers first, then other teams (rare) below a divider, then an
admin-only "Add receiver". A single-receiver **admin** now gets a menu (to add); a single-receiver
non-admin still gets a plain label.

**Files:**

- Modify: `ios/Caregiver/Home/HomeView.swift` (add sheet state, rewrite `receiverSwitcher`)

- [ ] **Step 1: Add Add-Receiver sheet state**

Next to `@State private var logTracker: Components.Schemas.Tracker?` add:

```swift
    @State private var showAddReceiver = false
```

- [ ] **Step 2: Present the Add-Receiver sheet**

After the existing `.sheet(isPresented:)` block for `logTracker` in `body`, add:

```swift
        .sheet(isPresented: $showAddReceiver) {
            AddReceiverView(me: me) {
                Task { await context.load(using: session) }
            }
        }
```

- [ ] **Step 3: Rewrite the `receiverSwitcher` to scope by team + add the admin action**

Replace the entire `receiverSwitcher` computed property with:

```swift
    @ViewBuilder private var receiverSwitcher: some View {
        let canAddReceiver = !me.adminGroups.isEmpty
        if context.receivers.count <= 1 && !canAddReceiver {
            Text(context.activeReceiver?.name ?? "")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.ink)
        } else {
            Menu {
                let activeGroupID = context.activeReceiver?.careGroupId
                // Active team first, then any other teams the user belongs to.
                let orderedMemberships = me.memberships.sorted { lhs, _ in
                    lhs.careGroupID == activeGroupID
                }
                ForEach(Array(orderedMemberships.enumerated()), id: \.element.careGroupID) { index, membership in
                    let groupReceivers = context.receivers.filter { $0.careGroupId == membership.careGroupID }
                    if !groupReceivers.isEmpty {
                        if index > 0 { Divider() }
                        Section(membership.name) {
                            ForEach(groupReceivers, id: \.receiverId) { receiver in
                                Button {
                                    context.setActive(receiver)
                                } label: {
                                    if receiver.receiverId == context.activeReceiverID {
                                        Label(receiver.name, systemImage: "checkmark")
                                    } else {
                                        Text(receiver.name)
                                    }
                                }
                            }
                        }
                    }
                }
                if canAddReceiver {
                    Divider()
                    Button {
                        showAddReceiver = true
                    } label: {
                        Label("Add receiver", systemImage: "plus")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(context.activeReceiver?.name ?? "")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.ink)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                }
            }
        }
    }
```

> Note: `activeReceiverID` is optional and `setActive` already persists it (see `ReceiverContext`).
> The checkmark compares against `context.activeReceiverID`, matching the pre-refinement behavior.

- [ ] **Step 4: Build + test**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Home/HomeView.swift
git commit -m "feat(ios): scope receiver dropdown to active team, add admin add-receiver"
```

---

## Task 4: Home empty state — admin "Add tracker" CTA

Replace the dead `"No trackers yet. Add one in Settings."` message. Admins for the active receiver's
team get a direct "Add tracker" button that opens the existing `TemplatePickerView`; non-admins get an
informational message with no dead-end instruction.

**Files:**

- Modify: `ios/Caregiver/Home/HomeView.swift` (sheet state, `.empty` case, a small empty-state subview)

- [ ] **Step 1: Add Add-Tracker sheet state and an admin check**

Next to the other `@State` properties add:

```swift
    @State private var showAddTracker = false
```

And add a computed property next to `activeTeamName`:

```swift
    private var isAdminForActive: Bool {
        guard let groupID = context.activeReceiver?.careGroupId else { return false }
        return me.isAdmin(inCareGroup: groupID)
    }
```

- [ ] **Step 2: Swap the `.empty` case for a role-aware view**

In `body`'s `switch model.state`, replace:

```swift
            case .empty:
                EmptyStateView(message: "No trackers yet. Add one in Settings.")
```

with:

```swift
            case .empty:
                emptyState
```

Then add this computed property to `HomeView` (e.g. below `trackerList`):

```swift
    @ViewBuilder private var emptyState: some View {
        if isAdminForActive, context.activeReceiver != nil {
            VStack(spacing: Theme.Spacing.md) {
                EmptyStateView(message: "No trackers yet.")
                PrimaryButton(title: "Add tracker") {
                    showAddTracker = true
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        } else {
            EmptyStateView(message: "No trackers yet.")
        }
    }
```

> `PrimaryButton(title:)` with a trailing action closure is the design-system button
> (`ios/Caregiver/DesignSystem/Components.swift:76`); the exact form `PrimaryButton(title: "…") { … }`
> is already used in `TrackerDetailView.swift:18` and `EnableBiometricSheet.swift:26`.

- [ ] **Step 3: Present the Add-Tracker sheet**

After the `showAddReceiver` sheet added in Task 3, add:

```swift
        .sheet(isPresented: $showAddTracker) {
            if let receiver = context.activeReceiver {
                TemplatePickerView(receiverId: receiver.receiverId) {
                    Task { await reload() }
                }
            }
        }
```

- [ ] **Step 4: Build + test**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Home/HomeView.swift
git commit -m "feat(ios): admin add-tracker cta on empty home state"
```

---

## Task 5: Settings tap-through — un-orphan `ReceiverDetailView`

Today nothing pushes `Route.receiver`, so `ReceiverDetailView` (which holds add-tracker / rename /
archive) is unreachable. Give the Settings `NavigationStack` the same route destinations as Home (via a
shared modifier — DRY), and make Settings receiver rows tappable.

**Files:**

- Modify: `ios/Caregiver/App/RootView.swift` (extract destinations into a reusable modifier; apply to Home + Settings stacks)
- Modify: `ios/Caregiver/Settings/SettingsView.swift` (receiver rows → `NavigationLink`)

- [ ] **Step 1: Extract a shared route-destinations modifier**

In `ios/Caregiver/App/RootView.swift`, add at the bottom of the file (file scope):

```swift
private extension View {
    /// The app's shared `Route` destinations, applied to any `NavigationStack`
    /// that needs to push receiver / tracker / event screens.
    func appRouteDestinations(me: Me) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .receiver(let r): ReceiverDetailView(me: me, receiver: r)
            case .tracker(let t): TrackerDetailView(me: me, tracker: t)
            case .event(let ref): EventDetailView(tracker: ref.tracker, event: ref.event) {}
            }
        }
    }
}
```

- [ ] **Step 2: Use the modifier on the Home stack**

In `mainStack`, replace the Home stack:

```swift
            NavigationStack {
                HomeView(me: me)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .receiver(let r): ReceiverDetailView(me: me, receiver: r)
                        case .tracker(let t): TrackerDetailView(me: me, tracker: t)
                        case .event(let ref): EventDetailView(tracker: ref.tracker, event: ref.event) {}
                        }
                    }
            }
            .tabItem { Label("Home", systemImage: "house") }
```

with:

```swift
            NavigationStack {
                HomeView(me: me)
                    .appRouteDestinations(me: me)
            }
            .tabItem { Label("Home", systemImage: "house") }
```

- [ ] **Step 3: Apply the modifier to the Settings stack**

In `mainStack`, replace:

```swift
            NavigationStack { SettingsView(me: me) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
```

with:

```swift
            NavigationStack {
                SettingsView(me: me)
                    .appRouteDestinations(me: me)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
```

- [ ] **Step 4: Make Settings receiver rows tappable**

In `ios/Caregiver/Settings/SettingsView.swift`, replace:

```swift
                    ForEach(groupReceivers, id: \.receiverId) { receiver in
                        Text(receiver.name)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
```

with:

```swift
                    ForEach(groupReceivers, id: \.receiverId) { receiver in
                        NavigationLink(value: Route.receiver(receiver)) {
                            Text(receiver.name)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
```

- [ ] **Step 5: Build + test**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Caregiver/App/RootView.swift ios/Caregiver/Settings/SettingsView.swift
git commit -m "feat(ios): tap settings receiver into detail (un-orphan tracker mgmt)"
```

---

## Final verification

- [ ] **Full suite green**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Manual smoke (simulator), confirming the spec's acceptance behaviors:**
  - Home title shows the active receiver **and** the care-team name beneath it.
  - As an admin with no trackers: the empty state shows **Add tracker** → template picker → a created tracker appears.
  - Receiver dropdown shows the active team first; "Add receiver" appears for admins; switching receiver updates the title + team caption.
  - Settings → tap a receiver → `ReceiverDetailView` opens with its "+" add-tracker / rename / archive controls.

- [ ] **Open a PR (do not merge — Trevor merges)**

```bash
git push -u origin c1-ui-home-refinement
gh pr create --fill
```

---

## Self-review notes (author)

- **Spec coverage:** Refinement work items 1–4 map to Tasks 2, 3, 4, 5 respectively; Task 1 is the shared helper item 1 depends on. ✅
- **Type consistency:** `teamName(forCareGroup:)` / `isAdmin(inCareGroup:)` / `adminGroups` / `setActive` / `activeReceiverID` / `activeReceiver.careGroupId` all match existing signatures in `Session.swift` and `ReceiverContext.swift`. `TemplatePickerView(receiverId:onCreated:)`, `AddReceiverView(me:onAdded:)`, and `PrimaryButton(title:)` + trailing closure all verified against their definitions/call sites.
