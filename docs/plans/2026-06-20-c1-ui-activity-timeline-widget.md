# C1-UI Activity Timeline — Glass Widget Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confine the Activity timeline into its own glassy widget card, with the tab structured as a vertical stack of widget cards ready for future additions.

**Architecture:** Two small view-only changes: (1) extract the card-style glass into a reusable `.glassCard()` `View` extension in `Components.swift`; (2) restructure `ActivityView` so the tab is an outer `ScrollView` + `VStack` of widgets, with the timeline (date-nav header + steps/states) wrapped in `.glassCard()` and sizing to its content. No logic, data, or test changes.

**Tech Stack:** SwiftUI (iOS 17+), XcodeGen (`ios/project.yml` source of truth; `.xcodeproj` generated), `CaregiverAPI` client, XCTest. Build/test on the iPhone 17 simulator.

Source spec: `docs/specs/2026-06-19-c1-ui-activity-timeline-design.md` (see "Widget container — glass card").

---

## Preamble — branch & baseline

You are on branch `c1-ui-activity-timeline` (PR #24, based on `main`). The timeline (rail redesign +
layout fix) is already in place; this plan wraps it in a glass widget.

- [ ] **Confirm the baseline builds and tests pass**

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **` (49 tests). If it fails, stop and fix the baseline first.

> **Note:** Both tasks are view-only and gated by a green `xcodebuild test` (compiles + the 49-test
> suite stays green) — there are no unit-testable units here. If the simulator throws a transient
> "Application failed preflight checks", boot it explicitly (`xcrun simctl boot "iPhone 17"`, ignore
> "already booted") and re-run.

---

## File structure

| File                                          | Change                                                                            |
| --------------------------------------------- | --------------------------------------------------------------------------------- |
| `ios/Caregiver/DesignSystem/Components.swift` | **Modify** — add the reusable `.glassCard()` `View` extension                     |
| `ios/Caregiver/Activity/ActivityView.swift`   | **Modify** — outer `ScrollView` + `VStack` of widgets; timeline in `.glassCard()` |

---

## Task 1: Add a reusable `.glassCard()` modifier

Extract the card-style glass treatment (today inline in `TrackerCard`) into a `View` extension so the
timeline widget — and later `TrackerCard` — can share it.

**Files:**

- Modify: `ios/Caregiver/DesignSystem/Components.swift`

- [ ] **Step 1: Add the modifier**

At the **end** of `ios/Caregiver/DesignSystem/Components.swift` (after the last `struct`, at file
scope), add:

```swift
extension View {
    /// Wraps the view in the app's card-style glass: an ultra-thin material fill with a soft
    /// top-down white highlight, rounded corners, and a subtle shadow — all from `Theme` tokens.
    /// Content is clipped to the card's rounded corners (so full-width children like dividers and
    /// rows stay inside the card).
    func glassCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .shadow(color: Theme.Colors.ink.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
```

- [ ] **Step 2: Build + test (compiles, suite green)**

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`. (The modifier is unused until Task 2 — that's fine; it still
compiles.)

- [ ] **Step 3: Commit**

```bash
git add ios/Caregiver/DesignSystem/Components.swift
git commit -m "feat(ios): add reusable .glassCard() modifier"
```

---

## Task 2: Restructure `ActivityView` into a stack of widget cards

Make the tab an outer `ScrollView` of widget cards; wrap the timeline (date header + steps/states) in
`.glassCard()`. Give the non-loaded states a fixed height so the card has a sensible size (the shared
state views use `maxHeight: .infinity`, which would misbehave in a content-sized card).

**Files:**

- Modify: `ios/Caregiver/Activity/ActivityView.swift`

- [ ] **Step 1: Replace the `body`'s `Group`**

In `ios/Caregiver/Activity/ActivityView.swift`, replace this block:

```swift
        Group {
            if let receiver = context.activeReceiver {
                VStack(spacing: 0) {
                    dateHeader
                    Divider()
                    content(receiverID: receiver.receiverId)
                }
            } else {
                EmptyStateView(message: "No receiver selected.")
            }
        }
```

with:

```swift
        Group {
            if let receiver = context.activeReceiver {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        timelineWidget(receiverID: receiver.receiverId)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)
                }
                .refreshable { await reload() }
            } else {
                EmptyStateView(message: "No receiver selected.")
            }
        }
```

- [ ] **Step 2: Replace the `content(receiverID:)` function with `timelineWidget` + `dayContent`**

Replace this entire function:

```swift
    @ViewBuilder private func content(receiverID: String) -> some View {
        Group {
            switch model.state {
            case .loading:
                LoadingView()
            case .empty:
                EmptyStateView(message: "No activity on \(ActivityDay.label(for: selectedDate)).")
            case .error(let message):
                ErrorStateView(message: message) { Task { await reload() } }
            case .loaded(let refs):
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
                            NavigationLink(value: ref) {
                                ActivityRow(ref: ref, isFirst: index == 0, isLast: index == refs.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { await reload() }
            }
        }
        .task(id: DayKey(receiverID: receiverID, dayStart: ActivityDay.bounds(for: selectedDate).start)) {
            await reload()
        }
    }
```

with:

```swift
    /// The timeline as a self-contained glass widget: date-nav header + the day's content.
    @ViewBuilder private func timelineWidget(receiverID: String) -> some View {
        VStack(spacing: 0) {
            dateHeader
            Divider()
            dayContent
        }
        .glassCard()
        .task(id: DayKey(receiverID: receiverID, dayStart: ActivityDay.bounds(for: selectedDate).start)) {
            await reload()
        }
    }

    @ViewBuilder private var dayContent: some View {
        switch model.state {
        case .loading:
            LoadingView()
                .frame(height: 140)
        case .empty:
            EmptyStateView(message: "No activity on \(ActivityDay.label(for: selectedDate)).")
                .frame(height: 140)
        case .error(let message):
            ErrorStateView(message: message) { Task { await reload() } }
                .frame(height: 160)
        case .loaded(let refs):
            VStack(spacing: 0) {
                ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
                    NavigationLink(value: ref) {
                        ActivityRow(ref: ref, isFirst: index == 0, isLast: index == refs.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
```

> Why: the timeline steps move into a plain `VStack(spacing: 0)` (no inner `ScrollView`) so the card
> sizes to its content and the rail stays continuous; pull-to-refresh now lives on the outer
> `ScrollView` (Step 1). The loading/empty/error states get a fixed height so the card doesn't collapse
> or balloon (those shared views use `maxHeight: .infinity`).

- [ ] **Step 3: Build + test (compiles, suite green)**

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **` (49 tests).

- [ ] **Step 4: Commit**

```bash
git add ios/Caregiver/Activity/ActivityView.swift
git commit -m "feat(ios): confine activity timeline to a glass widget card"
```

---

## Final verification

- [ ] **Full suite green**

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Manual smoke (simulator):**
  - The Activity timeline is a single rounded glass card floating on the earthy background, with
    margins around it (not full-bleed).
  - The card contains the date-nav header, a divider, then the continuous-rail steps; it sizes to its
    content with empty space below (where future widgets would go).
  - Loading / "No activity" / error each render inside the card at a sensible height.
  - Pull-to-refresh works on the tab; tapping a step still opens `EventDetailView` and edits/deletes
    refresh the day; date nav (arrows / swipe / tap-to-jump) still works.

- [ ] **Push (updates PR #24 — do not merge; Trevor merges)**

```bash
git push
```

---

## Self-review notes (author)

- **Spec coverage:** reusable `.glassCard()` (Task 1); tab as a `ScrollView`/`VStack` of widgets with
  the timeline wrapped in the card (Task 2 Step 1); date-nav + steps + states inside the card sizing to
  content with no inner scroll (Task 2 Step 2); states-inside-card with fixed heights; outer
  pull-to-refresh. Non-goals respected (no second widget, no capped-height internal scroll, no
  `TrackerCard` refactor).
- **Type consistency:** `glassCard()` is defined in Task 1 and used in Task 2. `timelineWidget`/
  `dayContent` replace `content(receiverID:)`; `DayKey`, `ActivityDay.bounds`/`label`, `ActivityRow(ref:
isFirst:isLast:)`, `reload()`, `dateHeader`, `datePickerSheet` are all existing members left intact.
  `Theme.Spacing.{md,lg}`, `Theme.Radius.card`, `Theme.Colors.ink` exist.
- **Both commits build green:** Task 1's modifier compiles unused; Task 2 consumes it.
