# C1-UI Activity Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Activity tab placeholder with a single-day, cross-tracker event timeline for the active receiver, with date navigation and tap-to-detail.

**Architecture:** Pure client-side aggregation (no backend change). `ActivityModel` loads the active receiver's trackers, fetches each tracker's events for the selected day (`listEvents` with `from`/`to` day bounds) concurrently, and merges them newest-first into `[EventRef]`. `ActivityView` renders a date-nav header + the day's rows, each pushing the existing `EventDetailView` (with its `onChange` wired to reload). Two pure units — day-bounds math and the merge/sort — get TDD; the SwiftUI views are gated by a green build.

**Tech Stack:** SwiftUI (iOS 17+), XcodeGen (`ios/project.yml` is source of truth; `.xcodeproj` is generated), the generated `CaregiverAPI` Swift client, XCTest. Build/test runs on the iPhone 17 simulator.

Source spec: `docs/specs/2026-06-19-c1-ui-activity-timeline-design.md`.

---

## Preamble — branch & baseline

You are on branch `c1-ui-activity-timeline`, based on `main` (which already contains the C1-UI
foundation from PR #23). The only change so far is the design spec.

- [ ] **Confirm the baseline builds and tests pass before changing anything**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **` (the C1-UI suite, ~38 tests). If it fails, stop and fix the baseline
first.

> **Note on view tasks:** SwiftUI views are not unit-tested in this repo. Tasks 3 and 4 are gated by a
> successful `xcodebuild test` (compiles + the existing suite stays green). Tasks 1 and 2 contain the
> pure logic and get real TDD (red → green).

---

## File structure

| File                                          | Responsibility                                                           | Change      |
| --------------------------------------------- | ------------------------------------------------------------------------ | ----------- |
| `ios/Caregiver/Activity/ActivityDay.swift`    | Pure date math: day bounds + header label                                | **Create**  |
| `ios/CaregiverTests/ActivityDayTests.swift`   | Tests for `ActivityDay`                                                  | **Create**  |
| `ios/Caregiver/Activity/ActivityModel.swift`  | Load + merge a day's events into `[EventRef]`; load state machine        | **Create**  |
| `ios/CaregiverTests/ActivityMergeTests.swift` | Tests for `ActivityModel.merge`                                          | **Create**  |
| `ios/Caregiver/Activity/ActivityRow.swift`    | One event row: time · color dot + tracker name · value summary           | **Create**  |
| `ios/Caregiver/Activity/ActivityView.swift`   | Screen: date-nav header, day list, states, `EventRef` detail destination | **Rewrite** |

New files in `ios/Caregiver/Activity/` and `ios/CaregiverTests/` are auto-included by XcodeGen (both
directories are globbed in `ios/project.yml`); run `xcodegen generate` before building.

---

## Task 1: `ActivityDay` — day bounds + header label (TDD)

The two pure date helpers the view and model need. No app or generated types involved, so this is the
cleanest TDD unit.

**Files:**

- Create: `ios/Caregiver/Activity/ActivityDay.swift`
- Test: `ios/CaregiverTests/ActivityDayTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/CaregiverTests/ActivityDayTests.swift`:

```swift
import XCTest
@testable import Caregiver

final class ActivityDayTests: XCTestCase {
    // Fixed gregorian calendar in a fixed zone so the math is deterministic.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    func testBoundsAreStartOfDayToNextMidnight() {
        // 2026-06-17 14:30 America/Chicago
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 14, minute: 30))!
        let b = ActivityDay.bounds(for: date, calendar: cal)
        XCTAssertEqual(b.start, cal.date(from: DateComponents(year: 2026, month: 6, day: 17))!)
        XCTAssertEqual(b.end, cal.date(from: DateComponents(year: 2026, month: 6, day: 18))!)
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 24 * 60 * 60, accuracy: 1)
    }

    func testLabelToday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!
        let same = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 20))!
        XCTAssertEqual(ActivityDay.label(for: same, relativeTo: now, calendar: cal), "Today")
    }

    func testLabelYesterday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!
        let prev = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 23))!
        XCTAssertEqual(ActivityDay.label(for: prev, relativeTo: now, calendar: cal), "Yesterday")
    }

    func testLabelOlderUsesWeekdayAndDate() {
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!
        let older = cal.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 9))!
        // 2026-06-14 is a Sunday.
        XCTAssertEqual(ActivityDay.label(for: older, relativeTo: now, calendar: cal), "Sun, Jun 14")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail (no such type)**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityDayTests
```

Expected: FAIL — `cannot find 'ActivityDay' in scope`.

- [ ] **Step 3: Implement `ActivityDay`**

Create `ios/Caregiver/Activity/ActivityDay.swift`:

```swift
import Foundation

/// Pure date helpers for the Activity daily timeline.
enum ActivityDay {
    /// The half-open day window `[startOfDay, nextMidnight)` for `date` in `calendar`.
    static func bounds(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    /// "Today" / "Yesterday" / weekday + medium date (e.g. "Sun, Jun 14").
    static func label(for date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let startToday = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityDayTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Caregiver/Activity/ActivityDay.swift ios/CaregiverTests/ActivityDayTests.swift ios/project.yml
git commit -m "feat(ios): add ActivityDay date helpers for the activity timeline"
```

---

## Task 2: `ActivityModel` — state, merge (TDD), and load

The model owns the load state machine and the cross-tracker merge. The pure `merge` is TDD'd; `load`
(networking) is gated by the build + the existing suite.

**Files:**

- Create: `ios/Caregiver/Activity/ActivityModel.swift`
- Test: `ios/CaregiverTests/ActivityMergeTests.swift`

- [ ] **Step 1: Write the failing tests for `merge`**

Create `ios/CaregiverTests/ActivityMergeTests.swift`:

```swift
import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class ActivityMergeTests: XCTestCase {
    private func tracker(_ id: String) -> Components.Schemas.Tracker {
        .init(
            trackerId: id, receiverId: "r", careGroupId: "g",
            name: "T-\(id)", kind: .measurement, fields: [],
            createdBy: "u", createdAt: Date(timeIntervalSince1970: 0), archived: false
        )
    }

    private func event(_ id: String, at seconds: TimeInterval) -> Components.Schemas.Event {
        .init(
            trackerId: "t", eventId: id, careGroupId: "g", receiverId: "r",
            values: .init(additionalProperties: try! OpenAPIObjectContainer(unvalidatedValue: [:])),
            occurredAt: Date(timeIntervalSince1970: seconds),
            loggedBy: "u", createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testMergeSortsNewestFirstAcrossTrackers() {
        let t1 = tracker("1"); let t2 = tracker("2")
        let input: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = [
            (t1, [event("a", at: 100), event("b", at: 300)]),
            (t2, [event("c", at: 200)]),
        ]
        let refs = ActivityModel.merge(input)
        XCTAssertEqual(refs.map { $0.event.eventId }, ["b", "c", "a"])
    }

    func testMergeEmptyInputIsEmpty() {
        XCTAssertTrue(ActivityModel.merge([]).isEmpty)
    }

    func testMergeTieBreaksDeterministicallyByEventId() {
        let t1 = tracker("1")
        let input: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = [
            (t1, [event("y", at: 100), event("x", at: 100)]),
        ]
        // Equal timestamps → stable, deterministic order by eventId ascending.
        XCTAssertEqual(ActivityModel.merge(input).map { $0.event.eventId }, ["x", "y"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityMergeTests
```

Expected: FAIL — `cannot find 'ActivityModel' in scope`.

- [ ] **Step 3: Implement `ActivityModel`**

Create `ios/Caregiver/Activity/ActivityModel.swift`:

```swift
import Foundation
import CaregiverAPI

@MainActor
@Observable
final class ActivityModel {
    enum State: Equatable {
        case loading
        case loaded([EventRef])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading

    /// Flattens per-tracker events into `EventRef`s, newest-first; ties broken by
    /// `eventId` ascending so the order is deterministic.
    static func merge(_ perTracker: [(Components.Schemas.Tracker, [Components.Schemas.Event])]) -> [EventRef] {
        perTracker
            .flatMap { tracker, events in events.map { EventRef(tracker: tracker, event: $0) } }
            .sorted { lhs, rhs in
                if lhs.event.occurredAt != rhs.event.occurredAt {
                    return lhs.event.occurredAt > rhs.event.occurredAt
                }
                return lhs.event.eventId < rhs.event.eventId
            }
    }

    /// Loads the active receiver's events for `date` across all its (non-archived) trackers.
    func load(receiverID: String, date: Date, using session: Session) async {
        state = .loading
        let bounds = ActivityDay.bounds(for: date)
        let api = session.api  // capture the Sendable client for use in child tasks
        do {
            let trackers = try await api.listTrackers(path: .init(receiverId: receiverID))
                .ok.body.json.filter { !$0.archived }
            let perTracker = try await withThrowingTaskGroup(
                of: (Components.Schemas.Tracker, [Components.Schemas.Event]).self
            ) { group in
                for tracker in trackers {
                    group.addTask {
                        let items = try await api.listEvents(
                            path: .init(trackerId: tracker.trackerId),
                            query: .init(from: bounds.start, to: bounds.end)
                        ).ok.body.json.items
                        return (tracker, items)
                    }
                }
                var results: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = []
                for try await pair in group { results.append(pair) }
                return results
            }
            let refs = Self.merge(perTracker)
            state = refs.isEmpty ? .empty : .loaded(refs)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }
}
```

> If the compiler rejects capturing `api` in the child task on Sendable grounds, fall back to a
> sequential `for tracker in trackers { ... }` loop awaiting each `listEvents` in turn — correctness is
> identical and the merge still sorts globally. Report this as DONE_WITH_CONCERNS if you take the
> fallback.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -only-testing:CaregiverTests/ActivityMergeTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the full suite to confirm `load` compiles and nothing regressed**

Run:

```bash
cd ios && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Caregiver/Activity/ActivityModel.swift ios/CaregiverTests/ActivityMergeTests.swift ios/project.yml
git commit -m "feat(ios): add ActivityModel (load + merge) for the activity timeline"
```

---

## Task 3: `ActivityRow` — one timeline row

A focused row view: leading time, a color dot + tracker name, and the one-line value summary.

**Files:**

- Create: `ios/Caregiver/Activity/ActivityRow.swift`

- [ ] **Step 1: Implement `ActivityRow`**

Create `ios/Caregiver/Activity/ActivityRow.swift`:

```swift
import SwiftUI
import CaregiverAPI

/// One event in the daily timeline: time · (color dot + tracker name) · value summary.
struct ActivityRow: View {
    let ref: EventRef

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    private var dotColor: Color {
        ref.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(Self.timeFormatter.string(from: ref.event.occurredAt))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(ref.tracker.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Text(DynamicFormBuilder.display(values: ref.event.values, fields: ref.tracker.fields))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
```

- [ ] **Step 2: Build + test (compiles, suite green)**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Caregiver/Activity/ActivityRow.swift
git commit -m "feat(ios): add ActivityRow for the activity timeline"
```

---

## Task 4: `ActivityView` — screen, date nav, states, detail wiring

Rewrite the placeholder into the full timeline: a date-nav header that's always visible, the day's rows
as navigation links, the `EventRef` detail destination (reloading on change), and loading/empty/error
states. Swipe and a tap-to-jump date picker drive `selectedDate`.

**Files:**

- Rewrite: `ios/Caregiver/Activity/ActivityView.swift`

- [ ] **Step 1: Rewrite `ActivityView`**

Replace the entire contents of `ios/Caregiver/Activity/ActivityView.swift` with:

```swift
import SwiftUI
import CaregiverAPI

struct ActivityView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context

    @State private var model = ActivityModel()
    @State private var selectedDate = Date()
    @State private var showDatePicker = false

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
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
        .navigationTitle("Activity")
        .earthBackground()
        .navigationDestination(for: EventRef.self) { ref in
            EventDetailView(tracker: ref.tracker, event: ref.event) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }

    // MARK: Reload

    private func reload() async {
        guard let id = context.activeReceiver?.receiverId else { return }
        await model.load(receiverID: id, date: selectedDate, using: session)
    }

    // MARK: Date header

    private var dateHeader: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            Button { showDatePicker = true } label: {
                Text(ActivityDay.label(for: selectedDate))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(isToday)
                .opacity(isToday ? 0.3 : 1)
        }
        .font(.headline)
        .foregroundStyle(Theme.Colors.accent)
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width > 0 { shiftDay(-1) }
                    else if value.translation.width < 0 { shiftDay(1) }
                }
        )
    }

    private func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        // No future days.
        if delta > 0 && next > Date() && !Calendar.current.isDateInToday(next) { return }
        selectedDate = next
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Day", selection: $selectedDate, in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Jump to day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Day content

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
                List {
                    ForEach(refs, id: \.self) { ref in
                        NavigationLink(value: ref) { ActivityRow(ref: ref) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await reload() }
            }
        }
        .task(id: DayKey(receiverID: receiverID, dayStart: ActivityDay.bounds(for: selectedDate).start)) {
            await reload()
        }
    }
}

/// Reload trigger: re-runs when the active receiver or the selected day changes.
private struct DayKey: Equatable {
    let receiverID: String
    let dayStart: Date
}
```

- [ ] **Step 2: Build + test (compiles, suite green)**

Run:

```bash
cd ios && xcodegen generate && xcodebuild test \
  -scheme Caregiver -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Caregiver/Activity/ActivityView.swift
git commit -m "feat(ios): activity tab daily timeline view"
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

Expected: `** TEST SUCCEEDED **` (existing suite + the new `ActivityDayTests` and `ActivityMergeTests`).

- [ ] **Manual smoke (simulator), confirming the spec's acceptance behaviors:**
  - Activity tab opens on **Today** with the active receiver's events from all trackers, newest-first.
  - Prev arrow / swipe-right goes back a day; next arrow / swipe-left advances; **next is disabled on
    today**.
  - Tapping the date label opens a graphical picker bounded at today; selecting a past day loads it.
  - A day with no events shows "No activity on …".
  - Tapping an event opens `EventDetailView`; editing or deleting it and returning **refreshes the
    day**.
  - Switching the active receiver on Home changes what Activity shows.

- [ ] **Open a PR (do not merge — Trevor merges)**

```bash
git push -u origin c1-ui-activity-timeline
gh pr create --base main --fill
```

---

## Self-review notes (author)

- **Spec coverage:** single-day + date-nav (Task 4), tap→detail with reload-on-change (Task 4 nav
  destination), client aggregation across trackers (Task 2 `load`), newest-first merge (Task 2
  `merge`), day bounds (Task 1), row layout (Task 3), states incl. no-receiver/empty/error (Task 4).
  Non-goals respected (no backend, no pagination, no filter/search, no future dates).
- **Type consistency:** `EventRef(tracker:event:)` (Route.swift, `Hashable`), `Components.Schemas`
  `Tracker`/`Event`/`Field` constructors and `.values`/`.occurredAt`/`.eventId`/`.archived` match the
  OpenAPI schema and the existing `makeEvent` test helper. `session.api.listTrackers(path:)` /
  `listEvents(path:query:)` and `.ok.body.json` / `.items` match `HomeModel` and `TrackerDetailModel`
  usage. `DynamicFormBuilder.display(values:fields:)`, `Color(hex:)`, `EmptyStateView`,
  `ErrorStateView`, `LoadingView`, `EventDetailView(tracker:event:onChange:)`, `Theme.*` all exist.
- **Flagged risk:** the concurrent `withThrowingTaskGroup` capture of `api` (Task 2) — fallback to a
  sequential loop documented inline if Sendable checking complains.
