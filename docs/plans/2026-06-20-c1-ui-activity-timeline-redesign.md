# C1-UI Activity Timeline Rail Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Activity daily timeline as a vertical stepper rail — earliest event at the top, a day/night icon + time in a left gutter, a tracker-colored node on a continuous rail, and theme colors that blend with the earthy background.

**Architecture:** Four small changes to the existing (PR #24) Activity files: add a pure `ActivityDay.isDaytime` helper (TDD), flip `ActivityModel.merge` to oldest-first (TDD), rewrite `ActivityRow` into a gutter+rail+content stepper row using `Theme` tokens, and update `ActivityView`'s list to pass `isFirst`/`isLast` and make rows transparent.

**Tech Stack:** SwiftUI (iOS 17+), XcodeGen (`ios/project.yml` source of truth; `.xcodeproj` generated), generated `CaregiverAPI` client, XCTest. Build/test on the iPhone 17 simulator.

Source spec: `docs/specs/2026-06-19-c1-ui-activity-timeline-design.md` (see the "Row layout — timeline rail" section and the 2026-06-20 redesign notes).

---

## Preamble — branch & baseline

You are on branch `c1-ui-activity-timeline` (PR #24, based on `main`). The Activity timeline is already
built; this plan restyles it.

- [ ] **Confirm the baseline builds and tests pass**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **` (45 tests). If it fails, stop and fix the baseline first.

> **Note:** SwiftUI views are not unit-tested in this repo. Tasks 3 and 4 are gated by a green
> `xcodebuild test` (compiles + suite stays green). Tasks 1 and 2 are pure logic and get real TDD.
> If the simulator throws a transient "Application failed preflight checks", boot it explicitly
> (`xcrun simctl boot "iPhone 17"`, ignore "already booted") and re-run.

---

## File structure

| File                                          | Change                                                                   |
| --------------------------------------------- | ------------------------------------------------------------------------ |
| `ios/Caregiver/Activity/ActivityDay.swift`    | **Modify** — add `isDaytime(_:calendar:)`                                |
| `ios/CaregiverTests/ActivityDayTests.swift`   | **Modify** — add `isDaytime` boundary tests                              |
| `ios/Caregiver/Activity/ActivityModel.swift`  | **Modify** — flip `merge` sort to oldest-first (ascending)               |
| `ios/CaregiverTests/ActivityMergeTests.swift` | **Modify** — flip expectations to ascending                              |
| `ios/Caregiver/Activity/ActivityRow.swift`    | **Rewrite** — gutter + rail + content stepper; `isFirst`/`isLast`; Theme |
| `ios/Caregiver/Activity/ActivityView.swift`   | **Modify** — `ForEach` with index; transparent rows; hidden separators   |

---

## Task 1: `ActivityDay.isDaytime` (TDD)

The sun/moon split: daytime is hours 6:00–17:59; everything else is night.

**Files:**

- Modify: `ios/Caregiver/Activity/ActivityDay.swift`
- Modify (test): `ios/CaregiverTests/ActivityDayTests.swift`

- [ ] **Step 1: Add the failing boundary tests**

In `ios/CaregiverTests/ActivityDayTests.swift`, add these four methods inside the `ActivityDayTests`
class (e.g. just before the closing `}` of the class). The `cal` property already exists in this file.

```swift
    func testIsDaytimeFalseJustBeforeSix() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 5, minute: 59))!
        XCTAssertFalse(ActivityDay.isDaytime(d, calendar: cal))
    }

    func testIsDaytimeTrueAtSix() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 6))!
        XCTAssertTrue(ActivityDay.isDaytime(d, calendar: cal))
    }

    func testIsDaytimeTrueJustBeforeEighteen() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 17, minute: 59))!
        XCTAssertTrue(ActivityDay.isDaytime(d, calendar: cal))
    }

    func testIsDaytimeFalseAtEighteen() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 18))!
        XCTAssertFalse(ActivityDay.isDaytime(d, calendar: cal))
    }
```

- [ ] **Step 2: Run the tests to verify they FAIL (no such method)**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityDayTests
```

Expected: FAIL — `type 'ActivityDay' has no member 'isDaytime'`.

- [ ] **Step 3: Implement `isDaytime`**

In `ios/Caregiver/Activity/ActivityDay.swift`, add this method inside the `ActivityDay` enum (e.g.
after `label(...)`):

```swift
    /// True when `date`'s hour is in 6:00–17:59 (daytime → sun; otherwise → moon).
    static func isDaytime(_ date: Date, calendar: Calendar = .current) -> Bool {
        (6..<18).contains(calendar.component(.hour, from: date))
    }
```

- [ ] **Step 4: Run the tests to verify they PASS**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityDayTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Activity/ActivityDay.swift ios/CaregiverTests/ActivityDayTests.swift
git commit -m "feat(ios): add ActivityDay.isDaytime for timeline sun/moon icon"
```

---

## Task 2: Flip `merge` to oldest-first (TDD)

The rail puts the earliest event at the top, so `merge` must sort ascending (was descending).

**Files:**

- Modify (test): `ios/CaregiverTests/ActivityMergeTests.swift`
- Modify: `ios/Caregiver/Activity/ActivityModel.swift`

- [ ] **Step 1: Update the test to expect ascending order (this makes it fail)**

In `ios/CaregiverTests/ActivityMergeTests.swift`, replace the `testMergeSortsNewestFirstAcrossTrackers`
method with:

```swift
    func testMergeSortsOldestFirstAcrossTrackers() {
        let t1 = tracker("1"); let t2 = tracker("2")
        let input: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = [
            (t1, [event("a", at: 100), event("b", at: 300)]),
            (t2, [event("c", at: 200)]),
        ]
        let refs = ActivityModel.merge(input)
        XCTAssertEqual(refs.map { $0.event.eventId }, ["a", "c", "b"])
    }
```

(The empty-input and tie-break tests are unchanged — the tie-break is still `eventId` ascending, so it
still expects `["x", "y"]`.)

- [ ] **Step 2: Run the merge tests to verify the new one FAILS**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityMergeTests
```

Expected: FAIL — `testMergeSortsOldestFirstAcrossTrackers` asserts `["a","c","b"]` but the current
descending sort returns `["b","c","a"]`.

- [ ] **Step 3: Flip the sort to ascending**

In `ios/Caregiver/Activity/ActivityModel.swift`, in `merge`, change the timestamp comparison from `>` to
`<`. Replace:

```swift
                if lhs.event.occurredAt != rhs.event.occurredAt {
                    return lhs.event.occurredAt > rhs.event.occurredAt
                }
                return lhs.event.eventId < rhs.event.eventId
```

with:

```swift
                if lhs.event.occurredAt != rhs.event.occurredAt {
                    return lhs.event.occurredAt < rhs.event.occurredAt
                }
                return lhs.event.eventId < rhs.event.eventId
```

Also update the doc comment above `merge` from "newest-first" to "oldest-first":

```swift
    /// Flattens per-tracker events into `EventRef`s, oldest-first (earliest event first); ties
    /// broken by `eventId` ascending so the order is deterministic.
```

- [ ] **Step 4: Run the merge tests to verify they PASS**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityMergeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Activity/ActivityModel.swift ios/CaregiverTests/ActivityMergeTests.swift
git commit -m "feat(ios): sort activity timeline oldest-first for the rail"
```

---

## Task 3: Rewrite `ActivityRow` + wire `ActivityView` (one task, builds green together)

Gutter (day/night icon + time) · rail (line + tracker-colored node, trimmed at the ends) · content
(name + value), all `Theme` colors — plus the `ActivityView` call-site change in the **same task**,
because the new `isFirst`/`isLast` parameters break `ActivityView` until it's updated. Doing both here
keeps every commit building green.

**Files:**

- Rewrite: `ios/Caregiver/Activity/ActivityRow.swift`
- Modify: `ios/Caregiver/Activity/ActivityView.swift`

- [ ] **Step 1: Replace the `ActivityRow` file contents**

Replace the ENTIRE contents of `ios/Caregiver/Activity/ActivityRow.swift` with:

```swift
import SwiftUI
import CaregiverAPI

/// One step in the daily timeline rail: a day/night icon + time in the gutter, a tracker-colored
/// node on a continuous vertical rail (trimmed at the first/last step), then the tracker name and
/// value summary. Earliest event renders at the top.
struct ActivityRow: View {
    let ref: EventRef
    let isFirst: Bool
    let isLast: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    private var isDaytime: Bool { ActivityDay.isDaytime(ref.event.occurredAt) }

    private var nodeColor: Color {
        ref.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent
    }

    private var railColor: Color { Theme.Colors.ink.opacity(0.15) }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            // Gutter: day/night icon + time
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.fill")
                    .font(.caption)
                    .foregroundStyle(isDaytime ? Theme.Colors.amber : Theme.Colors.textSecondary)
                Text(Self.timeFormatter.string(from: ref.event.occurredAt))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(width: 52)

            // Rail: continuous line with a tracker-colored node; trimmed above first / below last.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : railColor)
                    .frame(width: 2)
                Circle()
                    .fill(nodeColor)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(isLast ? Color.clear : railColor)
                    .frame(width: 2)
            }
            .frame(width: 24)

            // Content: tracker name + value summary
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(ref.tracker.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(DynamicFormBuilder.display(values: ref.event.values, fields: ref.tracker.fields))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
```

- [ ] **Step 2: Update `ActivityView`'s `.loaded` list to feed the rail**

In `ios/Caregiver/Activity/ActivityView.swift`, replace this block:

```swift
            case .loaded(let refs):
                List {
                    ForEach(refs, id: \.self) { ref in
                        NavigationLink(value: ref) { ActivityRow(ref: ref) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await reload() }
```

with:

```swift
            case .loaded(let refs):
                List {
                    ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
                        NavigationLink(value: ref) {
                            ActivityRow(ref: ref, isFirst: index == 0, isLast: index == refs.count - 1)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await reload() }
```

- [ ] **Step 3: Build + test (full suite must stay green)**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **` (49 tests: 45 baseline + 4 new `isDaytime` tests; the merge test was
renamed, not added).

- [ ] **Step 4: Commit both files together**

```bash
git add ios/Caregiver/Activity/ActivityRow.swift ios/Caregiver/Activity/ActivityView.swift
git commit -m "feat(ios): restyle activity timeline as a stepper rail (gutter, node, theme colors)"
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

- [ ] **Manual smoke (simulator):**
  - Activity tab shows the day's events on a vertical rail, **earliest at the top**.
  - Each row has a sun (daytime) or moon (evening/night) icon beside its time.
  - The rail is a continuous line with a tracker-colored node per event; it starts at the first node and
    ends at the last (no stubs past the ends).
  - The earthy background shows through between rows (no opaque row fills, no row separators).
  - Tapping a row still opens `EventDetailView`; edit/delete still refreshes the day.

- [ ] **Push (updates PR #24 — do not merge; Trevor merges)**

```bash
git push
```

---

## Self-review notes (author)

- **Spec coverage:** ascending order (Task 2), sun/moon split + icon (Tasks 1 & 3), rail with
  tracker-colored node trimmed at ends (Task 3), theme colors + transparent rows blending with
  `.earthBackground()` (Tasks 3 & 4), equal-spaced stepper / no scaled axis (Task 3 layout). Date-nav,
  states, and navigation are unchanged and out of scope.
- **Type consistency:** `ActivityRow(ref:isFirst:isLast:)` is defined in Task 3 and called with exactly
  those labels in Task 4. `ActivityDay.isDaytime(_:calendar:)` defined in Task 1, used in Task 3.
  `merge` comparator change keeps the `eventId`-ascending tiebreak. `Theme.Colors.{amber,ink,accent,
textPrimary,textSecondary}`, `Theme.Spacing.{xs,sm}`, `Theme.Typography.{caption,headline,body}`,
  `Color(hex:)`, `DynamicFormBuilder.display(values:fields:)` all exist.
- **Green-build note:** `ActivityRow`'s new `isFirst`/`isLast` parameters break `ActivityView` until its
  call site is updated, so Task 3 changes **both** files and commits them together — every commit builds
  green. (Tasks 1 and 2 are independent and build green on their own.)
