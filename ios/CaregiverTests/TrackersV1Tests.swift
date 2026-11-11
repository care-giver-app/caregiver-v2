import XCTest
@testable import Caregiver

/// Fixed instants and zones throughout: nothing here reads the clock or the device zone.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!
    static let utc = TimeZone(identifier: "UTC")!

    static func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Sunday Nov 8 2026, 12:00 noon in Chicago (CST, UTC-6).
    static let now = at("2026-11-08T18:00:00Z")

    static func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    static func tracker(_ name: String, status: TrackerStatus = .active, attention: Bool = false,
                        last: Date? = nil, paused: Date? = nil) -> TrackerItem {
        TrackerItem(id: name, name: name, icon: "heart", color: "#1c8fe0", status: status,
                    lastLoggedAt: last, pausedAt: paused, needsAttention: attention)
    }
}

// MARK: - Trackers list

@MainActor
final class TrackerListFilterTests: XCTestCase {
    private let trackers = [
        Fixed.tracker("Blood pressure"),
        Fixed.tracker("Meals", attention: true),
        Fixed.tracker("Medication", attention: true),
        Fixed.tracker("Walk", status: .paused),
        // The API never sends this; the filter still keeps a paused tracker out of trouble.
        Fixed.tracker("Zinc", status: .paused, attention: true),
    ]

    func testEachFilterHoldsItsTrackers() {
        XCTAssertEqual(trackers.filter(TrackerListFilter.active.includes).map(\.name),
                       ["Blood pressure", "Meals", "Medication"])
        XCTAssertEqual(trackers.filter(TrackerListFilter.needsAttention.includes).map(\.name),
                       ["Meals", "Medication"])
        XCTAssertEqual(trackers.filter(TrackerListFilter.paused.includes).map(\.name), ["Walk", "Zinc"])
    }

    func testModelOpensOnActiveWithCountsOnEveryChip() async {
        let trackers = trackers
        let model = TrackersListModel(receiver: TeamReceiver(id: "r", name: "Eleanor", timeZone: Fixed.chicago),
                                      service: trackersService { _ in trackers })
        await model.load()
        XCTAssertEqual(model.filter, .active)
        XCTAssertEqual(model.chipLabel(.active), "Active · 3")
        XCTAssertEqual(model.chipLabel(.needsAttention), "Needs attention · 2")
        XCTAssertEqual(model.chipLabel(.paused), "Paused · 2")
        XCTAssertFalse(model.hasNoTrackers)

        model.filter = .needsAttention
        XCTAssertEqual(model.visible.map(\.name), ["Meals", "Medication"], "served order is kept")
    }

    func testNoTrackersAtAllIsNotAnEmptyFilter() async {
        let model = TrackersListModel(receiver: TeamReceiver(id: "r", name: "Eleanor", timeZone: Fixed.chicago),
                                      service: trackersService { _ in [] })
        await model.load()
        XCTAssertTrue(model.hasNoTrackers)

        let paused = TrackersListModel(receiver: TeamReceiver(id: "r", name: "Eleanor", timeZone: Fixed.chicago),
                                       service: trackersService { _ in [Fixed.tracker("Walk", status: .paused)] })
        await paused.load()
        XCTAssertFalse(paused.hasNoTrackers)
        XCTAssertTrue(paused.visible.isEmpty)
    }

    func testARefreshThatFailsKeepsTheListAndSaysSo() async {
        let calls = Calls(failing: [2])
        let model = TrackersListModel(receiver: TeamReceiver(id: "r", name: "Eleanor", timeZone: Fixed.chicago),
                                      service: trackersService { _ in
                                          try await calls.next([Fixed.tracker("Meals")])
                                      })
        await model.load()
        await model.load()
        XCTAssertEqual(model.phase, .loaded([Fixed.tracker("Meals")]), "the list stays")
        XCTAssertTrue(model.refreshFailed)

        await model.load()
        XCTAssertFalse(model.refreshFailed, "a refresh that works clears the notice")
    }

    func testEveryLoadSaysRecencyAgainstAFreshNow() async {
        var clock = Fixed.now
        let model = TrackersListModel(receiver: TeamReceiver(id: "r", name: "Eleanor", timeZone: Fixed.chicago),
                                      service: trackersService { _ in [Fixed.tracker("Meals")] },
                                      clock: { clock })
        await model.load()
        XCTAssertEqual(model.now, Fixed.now)
        clock = Fixed.now.addingTimeInterval(3600)
        await model.load()  // what the view calls when the list reappears
        XCTAssertEqual(model.now, Fixed.now.addingTimeInterval(3600))
    }

    func testFailureIsShown() async {
        let model = TrackersListModel(receiver: TeamReceiver(id: "r", name: "Eleanor", timeZone: Fixed.chicago),
                                      service: trackersService { _ in throw URLError(.notConnectedToInternet) })
        await model.load()
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
    }
}

final class TrackerRecencyTextTests: XCTestCase {
    private func recency(_ last: Date?) -> String {
        TrackerText.recency(lastLoggedAt: last, now: Fixed.now, zone: Fixed.chicago)
    }

    func testRecency() {
        XCTAssertEqual(recency(nil), "Never logged")
        XCTAssertEqual(recency(Fixed.now.addingTimeInterval(-30)), "Logged just now")
        XCTAssertEqual(recency(Fixed.hoursAgo(5.0 / 60)), "Logged 5m ago")
        XCTAssertEqual(recency(Fixed.hoursAgo(2.5)), "Logged 2h ago")
        XCTAssertEqual(recency(Fixed.hoursAgo(24 * 3 + 1)), "Logged 3d ago")
        XCTAssertEqual(recency(Fixed.at("2026-10-19T17:00:00Z")), "Logged Oct 19")
        XCTAssertEqual(recency(Fixed.at("2025-11-03T17:00:00Z")), "Logged Nov 3, 2025")
    }

    func testPausedIsSaidInTheReceiversZone() {
        // 03:00 UTC on Nov 4 is still the evening of Nov 3 in Chicago.
        let paused = Fixed.at("2026-11-04T03:00:00Z")
        XCTAssertEqual(TrackerText.paused(at: paused, now: Fixed.now, zone: Fixed.chicago), "Paused Nov 3")
        XCTAssertEqual(TrackerText.paused(at: paused, now: Fixed.now, zone: Fixed.utc), "Paused Nov 4")
    }

    func testPausedRowSaysWhenItWasPausedInsteadOfRecency() {
        let walk = Fixed.tracker("Walk", status: .paused, last: Fixed.hoursAgo(2),
                                 paused: Fixed.at("2026-11-03T15:00:00Z"))
        XCTAssertEqual(TrackerText.rowSubtitle(walk, now: Fixed.now, zone: Fixed.chicago), "Paused Nov 3")
        let bp = Fixed.tracker("Blood pressure", last: Fixed.hoursAgo(2))
        XCTAssertEqual(TrackerText.rowSubtitle(bp, now: Fixed.now, zone: Fixed.chicago), "Logged 2h ago")
    }
}

// MARK: - Values

final class TrackerValueTextTests: XCTestCase {
    private let systolic = TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", options: [])
    private let weight = TrackerFieldInfo(id: "lb", label: "Weight", kind: .number, unit: "lb", options: [])
    private let minutes = TrackerFieldInfo(id: "min", label: "Minutes", kind: .number, unit: nil, options: [])
    private let given = TrackerFieldInfo(id: "given", label: "Given", kind: .boolean, unit: nil, options: [])
    private let note = TrackerFieldInfo(id: "what", label: "What", kind: .text, unit: nil, options: [])
    private let when = TrackerFieldInfo(id: "when", label: "Appointment", kind: .datetime, unit: nil, options: [])
    private let dose = TrackerFieldInfo(id: "dose", label: "Dose", kind: .choice, unit: nil, options: [
        ChoiceOptionInfo(id: "a", label: "Lisinopril 10 mg", retired: false),
        ChoiceOptionInfo(id: "b", label: "Lisinopril 5 mg", retired: true),
        ChoiceOptionInfo(id: "c", label: "Aspirin", retired: false),
    ])

    private func text(_ v: EntryValue, _ f: TrackerFieldInfo, zone: TimeZone = Fixed.chicago) -> String? {
        TrackerText.value(v, field: f, now: Fixed.now, zone: zone)
    }

    func testNumberWithItsUnit() {
        XCTAssertEqual(text(.number(152), systolic), "152 mmHg")
        XCTAssertEqual(text(.number(154.2), weight), "154.2 lb")
        XCTAssertEqual(text(.number(25), minutes), "25")
    }

    func testBoolean() {
        XCTAssertEqual(text(.bool(true), given), "Yes")
        XCTAssertEqual(text(.bool(false), given), "No")
    }

    func testChoiceJoinsLabelsIncludingRetiredOptions() {
        XCTAssertEqual(text(.list(["a", "b"]), dose), "Lisinopril 10 mg, Lisinopril 5 mg")
        XCTAssertEqual(text(.list(["b"]), dose), "Lisinopril 5 mg")
        XCTAssertNil(text(.list(["gone"]), dose))
    }

    func testText() {
        XCTAssertEqual(text(.string("Dinner"), note), "Dinner")
    }

    func testDatetimeIsReadInTheReceiversZone() {
        let iso = EntryValue.string("2026-11-04T02:30:00Z")
        XCTAssertEqual(text(iso, when), "Nov 3 at 8:30 PM")
        XCTAssertEqual(text(iso, when, zone: Fixed.utc), "Nov 4 at 2:30 AM")
        XCTAssertEqual(text(.string("2025-06-01T15:00:00.000Z"), when), "Jun 1, 2025 at 10:00 AM")
    }

    func testAValueOfTheWrongShapeIsLeftOut() {
        XCTAssertNil(text(.string("high"), systolic))
    }

    func testRowsFollowTheTrackersFieldOrderAndSkipWhatTheEntryLacks() {
        let entry = TrackerEntry(id: "e", state: .logged, at: Fixed.now,
                                 values: ["dose": .list(["a"]), "given": .bool(true), "stray": .number(1)],
                                 note: nil, byName: "Trevor")
        let rows = TrackerText.valueRows(entry, fields: [given, systolic, dose], now: Fixed.now, zone: Fixed.chicago)
        XCTAssertEqual(rows.map(\.label), ["Given", "Dose"])
        XCTAssertEqual(rows.map(\.value), ["Yes", "Lisinopril 10 mg"])
    }

    func testRawJSONValuesMap() {
        XCTAssertEqual(EntryValue(raw: 3), .number(3))
        XCTAssertEqual(EntryValue(raw: 3.5), .number(3.5))
        XCTAssertEqual(EntryValue(raw: true), .bool(true))
        XCTAssertEqual(EntryValue(raw: "x"), .string("x"))
        XCTAssertEqual(EntryValue(raw: ["a", "b"] as [(any Sendable)?]), .list(["a", "b"]))
    }
}

// MARK: - Entries

final class EntryTextTests: XCTestCase {
    private func when(_ iso: String, zone: TimeZone = Fixed.chicago) -> String {
        TrackerText.when(Fixed.at(iso), now: Fixed.now, zone: zone)
    }

    func testWhenIsTodayYesterdayWeekdayOrDateInTheReceiversZone() {
        XCTAssertEqual(when("2026-11-08T14:04:00Z"), "Today at 8:04 AM")
        // 05:30 UTC on Nov 8 is 11:30 PM on Nov 7 in Chicago — yesterday there, today in UTC.
        XCTAssertEqual(when("2026-11-08T05:30:00Z"), "Yesterday at 11:30 PM")
        XCTAssertEqual(when("2026-11-08T05:30:00Z", zone: Fixed.utc), "Today at 5:30 AM")
        XCTAssertEqual(when("2026-11-02T14:05:00Z"), "Monday at 8:05 AM")
        XCTAssertEqual(when("2026-10-30T14:15:00Z"), "Oct 30 at 9:15 AM")
    }

    func testBylineAndState() {
        let logged = TrackerEntry(id: "1", state: .logged, at: Fixed.now, values: [:], note: nil, byName: "Dana")
        let skipped = TrackerEntry(id: "2", state: .skipped, at: Fixed.now, values: [:], note: nil, byName: "Trevor")
        let unrecorded = TrackerEntry(id: "3", state: .unrecorded, at: Fixed.now, values: [:], note: nil, byName: nil)
        XCTAssertEqual(TrackerText.byline(logged), "Logged by Dana")
        XCTAssertEqual(TrackerText.byline(skipped), "Skipped by Trevor")
        XCTAssertEqual(TrackerText.byline(unrecorded), "Nothing was recorded")
        XCTAssertEqual(TrackerText.stateLabel(.unrecorded), "Unrecorded")
    }
}

// MARK: - Attention

final class TrackerAttentionTextTests: XCTestCase {
    private let fields = [TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", options: [])]

    private func say(_ item: TrackerAttentionItem) -> String {
        TrackerText.attention(item, fields: fields, now: Fixed.now, zone: Fixed.chicago)
    }

    func testUnrecorded() {
        // 14:00 UTC is 8:00 AM in Chicago.
        XCTAssertEqual(say(.unrecorded(occurrenceAt: Fixed.at("2026-11-08T14:00:00Z"))),
                       "The care due today at 8:00 AM went unrecorded.")
        XCTAssertEqual(say(.unrecorded(occurrenceAt: Fixed.at("2026-11-08T02:00:00Z"))),
                       "The care due yesterday at 8:00 PM went unrecorded.")
    }

    func testOutOfRangeNamesTheFieldTheValueAndTheRange() {
        XCTAssertEqual(say(.outOfRange(fieldID: "sys", value: 152, range: ValueRangeInfo(low: 90, high: 140))),
                       "Systolic was 152 mmHg, outside 90–140 mmHg.")
        XCTAssertEqual(say(.outOfRange(fieldID: "sys", value: 152, range: ValueRangeInfo(low: nil, high: 140))),
                       "Systolic was 152 mmHg, above 140 mmHg.")
        XCTAssertEqual(say(.outOfRange(fieldID: "sys", value: 82, range: ValueRangeInfo(low: 90, high: nil))),
                       "Systolic was 82 mmHg, below 90 mmHg.")
    }

    func testGapSaysHowLongAgainstWhatTheTeamAllows() {
        XCTAssertEqual(say(.gap(since: Fixed.hoursAgo(24 * 4 + 5), gapHours: 72)),
                       "Nothing logged in 4 days. The team allows 3 days without an entry.")
        XCTAssertEqual(say(.gap(since: Fixed.hoursAgo(30), gapHours: 12)),
                       "Nothing logged in 30 hours. The team allows 12 hours without an entry.")
        XCTAssertEqual(say(.gap(since: Fixed.hoursAgo(50), gapHours: 24)),
                       "Nothing logged in 2 days. The team allows 1 day without an entry.")
    }

    func testGapElapsedIsHoursUntilTwoDaysThenDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func elapsed(_ hours: Double) -> String {
            TrackerText.gapElapsed(since: now.addingTimeInterval(-hours * 3600), now: now)
        }
        XCTAssertEqual(elapsed(1), "1 hour")
        XCTAssertEqual(elapsed(47.9), "47 hours")
        XCTAssertEqual(elapsed(48), "2 days")
        XCTAssertEqual(elapsed(24 * 4 + 5), "4 days")
        XCTAssertEqual(TrackerText.gapElapsed(since: now.addingTimeInterval(3600), now: now), "0 hours",
                       "a gap that starts ahead of now counts as none")
    }

    func testDetailLines() {
        XCTAssertEqual(TrackerText.gapLine(hours: 72), "Alerts after 3 days without an entry")
        XCTAssertEqual(TrackerText.gapLine(hours: 24), "Alerts after 1 day without an entry")
        XCTAssertEqual(TrackerText.gapLine(hours: 36), "Alerts after 36 hours without an entry")
        XCTAssertEqual(TrackerText.scheduleCount(1), "1 schedule")
        XCTAssertEqual(TrackerText.scheduleCount(2), "2 schedules")
        XCTAssertEqual(TrackerText.neverLoggedGap(hours: 168), "Its 7-day gap counts from the day it was made.")
    }
}

// MARK: - Schedules

final class ScheduleTextTests: XCTestCase {
    func testFrequency() {
        XCTAssertEqual(TrackerText.frequency(intervalWeeks: 1), "every week")
        XCTAssertEqual(TrackerText.frequency(intervalWeeks: 2), "every 2 weeks")
        XCTAssertEqual(TrackerText.frequency(intervalWeeks: 3), "every 3 weeks")
        XCTAssertEqual(TrackerText.frequency(intervalWeeks: 4), "every month")
        XCTAssertEqual(TrackerText.frequency(intervalWeeks: 8), "every two months")
        XCTAssertEqual(TrackerText.frequency(intervalWeeks: 6), "every 6 weeks")
    }

    func testDaysAndClock() {
        XCTAssertEqual(TrackerText.days([.fr, .mo, .we]), "Mon, Wed, Fri")
        XCTAssertEqual(TrackerText.days(ScheduleWeekday.allCases), "Every day")
        XCTAssertEqual(TrackerText.clock("08:00"), "8:00 AM")
        XCTAssertEqual(TrackerText.clock("20:30"), "8:30 PM")
        XCTAssertEqual(TrackerText.clock("00:15"), "12:15 AM")
        XCTAssertEqual(TrackerText.clock("12:00"), "12:00 PM")
    }

    func testScheduleLine() {
        let daily = TrackerScheduleItem(id: "1", name: "Morning", days: ScheduleWeekday.allCases, interval: 1,
                                        time: "08:00", unrecordedAlert: false)
        XCTAssertEqual(TrackerText.scheduleLine(daily), "Every day · 8:00 AM")
        let monthly = TrackerScheduleItem(id: "2", name: "Refill", days: [.mo], interval: 4,
                                          time: "09:30", unrecordedAlert: true)
        XCTAssertEqual(TrackerText.scheduleLine(monthly), "Mon · every month · 9:30 AM")
    }

    func testEveryDayIsDecidedFromTheDaysNotTheirText() {
        func line(_ days: [ScheduleWeekday], every interval: Int) -> String {
            TrackerText.scheduleLine(TrackerScheduleItem(id: "s", name: "S", days: days, interval: interval,
                                                         time: "08:00", unrecordedAlert: false))
        }
        let shuffledWithRepeats: [ScheduleWeekday] = [.su, .mo, .tu, .we, .th, .fr, .sa, .mo]
        XCTAssertEqual(line(shuffledWithRepeats, every: 1), "Every day · 8:00 AM")
        XCTAssertEqual(line(ScheduleWeekday.allCases, every: 2), "All week · every 2 weeks · 8:00 AM")
        XCTAssertEqual(line(ScheduleWeekday.allCases, every: 4), "All week · every month · 8:00 AM")
        XCTAssertEqual(line(ScheduleWeekday.allCases, every: 8), "All week · every two months · 8:00 AM")
        XCTAssertEqual(line([.mo, .tu, .we, .th, .fr, .sa], every: 1), "Mon, Tue, Wed, Thu, Fri, Sat · every week · 8:00 AM")
    }
}

@MainActor
final class SchedulesV1ModelTests: XCTestCase {
    private let morning = TrackerScheduleItem(id: "1", name: "Morning", days: [.mo], interval: 1,
                                              time: "08:00", unrecordedAlert: false)

    func testARefreshThatFailsKeepsTheSchedules() async {
        let calls = Calls(failing: [2])
        let morning = morning
        var svc = service()
        svc.listSchedules = { _ in try await calls.next([morning]) }
        let model = SchedulesV1Model(trackerID: "t", service: svc)
        await model.load()
        await model.load()
        XCTAssertEqual(model.phase, .loaded([morning]))
        XCTAssertTrue(model.refreshFailed)
    }

    func testAFirstLoadThatFailsIsTheFailedScreen() async {
        var svc = service()
        svc.listSchedules = { _ in throw URLError(.timedOut) }
        let model = SchedulesV1Model(trackerID: "t", service: svc)
        await model.load()
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
        XCTAssertFalse(model.refreshFailed)
    }
}

@MainActor
final class TrackerDetailV1ModelTests: XCTestCase {
    private let profile = TrackerProfile(id: "t", name: "Meals", icon: "fork.knife", color: "#1c8fe0",
                                         status: .active, pausedAt: nil, fields: [], gapHours: 72,
                                         scheduleCount: 0, lastLoggedAt: nil, attention: [])

    func testARefreshThatFailsKeepsTheTrackerAndItsEntries() async {
        let detailCalls = Calls(failing: [2])
        let entryCalls = Calls(failing: [2])
        let profile = profile
        let first = TrackerEntry(id: "a", state: .logged, at: Fixed.now, values: [:], note: nil, byName: "Dana")
        var svc = service()
        svc.trackerDetail = { _ in try await detailCalls.next(profile) }
        svc.listEntries = { _, _ in try await entryCalls.next(EntriesPage(entries: [first], nextCursor: nil)) }
        let model = TrackerDetailV1Model(trackerID: "t", receiver: TeamReceiver(id: "r", name: "Eleanor",
                                                                                 timeZone: Fixed.chicago),
                                         service: svc)
        await model.load()
        XCTAssertFalse(model.showsRefreshFailure)

        await model.load()
        XCTAssertEqual(model.phase, .loaded(profile))
        XCTAssertEqual(model.entries.phase, .loaded)
        XCTAssertEqual(model.entries.entries.map(\.id), ["a"])
        XCTAssertTrue(model.refreshFailed)
        XCTAssertTrue(model.entries.refreshFailed)
        XCTAssertTrue(model.showsRefreshFailure)

        await model.load()
        XCTAssertFalse(model.showsRefreshFailure)
    }
}

// MARK: - Paging

/// Answers pages from a script and records every query.
private actor PageScript {
    private var pages: [EntriesPage]
    private(set) var queries: [EntriesQuery] = []
    init(_ pages: [EntriesPage]) { self.pages = pages }
    func next(_ query: EntriesQuery) -> EntriesPage {
        queries.append(query)
        return pages.isEmpty ? EntriesPage(entries: [], nextCursor: nil) : pages.removeFirst()
    }
}

@MainActor
final class EntriesPagerTests: XCTestCase {
    private func entry(_ id: String) -> TrackerEntry {
        TrackerEntry(id: id, state: .logged, at: Fixed.now, values: [:], note: nil, byName: "Trevor")
    }

    private func pager(_ script: PageScript) -> EntriesPager {
        EntriesPager(trackerID: "t") { _, query in await script.next(query) }
    }

    func testAppendsPagesWithoutDuplicatesAndStopsAtTheLastPage() async {
        let script = PageScript([
            EntriesPage(entries: [entry("a"), entry("b")], nextCursor: "c1"),
            EntriesPage(entries: [entry("b"), entry("c")], nextCursor: nil),
        ])
        let pager = pager(script)
        await pager.reload()
        XCTAssertEqual(pager.entries.map(\.id), ["a", "b"])
        XCTAssertFalse(pager.isExhausted)

        await pager.loadMore()
        XCTAssertEqual(pager.entries.map(\.id), ["a", "b", "c"])
        XCTAssertTrue(pager.isExhausted)

        await pager.loadMore()
        let queries = await script.queries
        XCTAssertEqual(queries.map(\.cursor), [nil, "c1"], "no call once the cursor runs out")
    }

    func testOnlyTheLastEntryAppearingAsksForMore() async {
        let script = PageScript([
            EntriesPage(entries: [entry("a"), entry("b")], nextCursor: "c1"),
            EntriesPage(entries: [entry("c")], nextCursor: nil),
        ])
        let pager = pager(script)
        await pager.reload()
        await pager.entryAppeared(entry("a"))
        XCTAssertEqual(pager.entries.count, 2)
        await pager.entryAppeared(entry("b"))
        XCTAssertEqual(pager.entries.map(\.id), ["a", "b", "c"])
    }

    func testChangingTheRangeStartsOverWithItsDates() async {
        let script = PageScript([
            EntriesPage(entries: [entry("a"), entry("b")], nextCursor: "c1"),
            EntriesPage(entries: [entry("x")], nextCursor: nil),
            EntriesPage(entries: [entry("a")], nextCursor: "c9"),
        ])
        let pager = pager(script)
        await pager.reload()

        let range = EntryDateRange(from: "2026-11-01", to: "2026-11-07")
        await pager.setRange(range)
        XCTAssertEqual(pager.entries.map(\.id), ["x"], "the old range's entries are gone")
        await pager.setRange(range)  // the same range again asks nothing

        await pager.setRange(nil)
        XCTAssertEqual(pager.entries.map(\.id), ["a"])

        let queries = await script.queries
        XCTAssertEqual(queries, [
            EntriesQuery(from: nil, to: nil, cursor: nil),
            EntriesQuery(from: "2026-11-01", to: "2026-11-07", cursor: nil),
            EntriesQuery(from: nil, to: nil, cursor: nil),
        ])
    }

    func testAFailedNextPageKeepsTheListAndCanBeRetried() async {
        actor Flaky {
            var calls = 0
            func next(_ q: EntriesQuery) throws -> EntriesPage {
                calls += 1
                if calls == 2 { throw URLError(.timedOut) }
                return q.cursor == nil
                    ? EntriesPage(entries: [TrackerEntry(id: "a", state: .logged, at: Date(timeIntervalSince1970: 0),
                                                         values: [:], note: nil, byName: nil)], nextCursor: "c1")
                    : EntriesPage(entries: [TrackerEntry(id: "b", state: .logged, at: Date(timeIntervalSince1970: 0),
                                                         values: [:], note: nil, byName: nil)], nextCursor: nil)
            }
        }
        let flaky = Flaky()
        let pager = EntriesPager(trackerID: "t") { _, q in try await flaky.next(q) }
        await pager.reload()
        await pager.loadMore()
        XCTAssertTrue(pager.moreFailed)
        XCTAssertEqual(pager.entries.map(\.id), ["a"])
        await pager.loadMore()
        XCTAssertFalse(pager.moreFailed)
        XCTAssertEqual(pager.entries.map(\.id), ["a", "b"])
    }

    func testARefreshReplacesTheListOnlyWhenTheFirstPageArrives() async {
        let script = PageScript([
            EntriesPage(entries: [entry("a"), entry("b")], nextCursor: "c1"),
            EntriesPage(entries: [entry("c")], nextCursor: nil),
            EntriesPage(entries: [entry("new"), entry("a")], nextCursor: "c2"),
        ])
        let gate = Gate()
        let pager = EntriesPager(trackerID: "t") { _, query in
            let page = await script.next(query)
            if page.entries.first?.id == "new" { await gate.wait() }
            return page
        }
        await pager.reload()
        await pager.loadMore()
        XCTAssertEqual(pager.entries.map(\.id), ["a", "b", "c"])

        let refreshing = Task { await pager.refresh() }
        await gate.untilWaiting()
        XCTAssertEqual(pager.phase, .loaded, "no spinner while it refreshes")
        XCTAssertEqual(pager.entries.map(\.id), ["a", "b", "c"], "the list stays until page 1 arrives")
        await gate.open()
        await refreshing.value

        XCTAssertEqual(pager.entries.map(\.id), ["new", "a"], "page 1 replaces the list")
        XCTAssertFalse(pager.isExhausted, "and brings its own cursor")
        XCTAssertFalse(pager.refreshFailed)
        let queries = await script.queries
        XCTAssertEqual(queries.map(\.cursor), [nil, "c1", nil])
    }

    func testARefreshThatFailsKeepsTheList() async {
        let calls = Calls(failing: [2])
        let a = entry("a")
        let pager = EntriesPager(trackerID: "t") { _, _ in
            try await calls.next(EntriesPage(entries: [a], nextCursor: nil))
        }
        await pager.reload()
        await pager.refresh()
        XCTAssertEqual(pager.phase, .loaded)
        XCTAssertEqual(pager.entries.map(\.id), ["a"])
        XCTAssertTrue(pager.refreshFailed)
    }

    func testDayStringIsTheReceiversDate() {
        // 03:00 UTC on Nov 4 is Nov 3 in Chicago.
        XCTAssertEqual(TrackerText.dayString(Fixed.at("2026-11-04T03:00:00Z"), zone: Fixed.chicago), "2026-11-03")
    }
}

// MARK: - Helpers

/// Answers every call with the value given, except the numbered calls (1-based), which fail.
private actor Calls {
    private let failing: Set<Int>
    private var count = 0
    init(failing: Set<Int>) { self.failing = failing }
    func next<T: Sendable>(_ value: T) throws -> T {
        count += 1
        if failing.contains(count) { throw URLError(.timedOut) }
        return value
    }
}

/// Holds a fetch until the test lets it go, so the test can look at the screen mid-flight.
private actor Gate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func untilWaiting() async {
        while waiter == nil && !isOpen { await Task.yield() }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

private func service(
    receivers: @escaping @Sendable (String) async throws -> [TeamReceiver] = { _ in [] },
    trackers: @escaping @Sendable (String) async throws -> [TrackerItem] = { _ in [] }
) -> TrackersService {
    TrackersService(
        listReceivers: receivers,
        listTrackers: trackers,
        trackerDetail: { _ in throw URLError(.badURL) },
        listEntries: { _, _ in EntriesPage(entries: [], nextCursor: nil) },
        listSchedules: { _ in [] }
    )
}

private func trackersService(_ trackers: @escaping @Sendable (String) async throws -> [TrackerItem]) -> TrackersService {
    service(trackers: trackers)
}
