import XCTest
@testable import Caregiver

/// Fixed instants and zones throughout: nothing here reads the clock or the device zone.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!
    static let denver = TimeZone(identifier: "America/Denver")!

    static func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Nov 8 05:30 UTC — still Saturday Nov 7 in Chicago and Denver.
    static let now = at("2026-11-08T05:30:00Z")
    static let nov7 = LocalDay(year: 2026, month: 11, day: 7)

    static let eleanor = TeamReceiver(id: "eleanor", name: "Eleanor", timeZone: chicago, canManage: true)
    static let walter = TeamReceiver(id: "walter", name: "Walter", timeZone: denver)

    static let medication = TrackerBadgeInfo(id: "medication", name: "Medication", icon: "pills", color: "#6f5fe0")
    static let meals = TrackerBadgeInfo(id: "meals", name: "Meals", icon: "fork.knife", color: "#1c8fe0")

    static func tracker(_ id: String, _ status: TrackerStatus) -> TrackerItem {
        TrackerItem(id: id, name: id, icon: "heart", color: "#1c8fe0", status: status, lastLoggedAt: nil,
                    pausedAt: nil, needsAttention: false)
    }

    static let unrecorded = AttentionItem(tracker: medication,
                                          attention: .unrecorded(entryID: "e1", occurrenceAt: at("2026-11-08T02:00:00Z")))
    static let gap = AttentionItem(tracker: meals, attention: .gap(since: at("2026-11-05T05:30:00Z"), gapHours: 24))

    static let upcoming = ReceiverEntryItem(tracker: medication, entry: TrackerEntry(
        id: "next", state: .scheduled, at: at("2026-11-08T14:00:00Z"), values: [:], note: nil, byName: nil,
        scheduleName: "Morning"))

    static let logged = DayItem.entry(ReceiverEntryItem(tracker: medication, entry: TrackerEntry(
        id: "logged", state: .logged, at: at("2026-11-07T14:05:00Z"), values: ["dose": .number(10)], note: nil,
        byName: "Dana")))
}

/// What each read was asked for, so a test can tell what loaded.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private(set) var days: [LocalDay] = []
    private var failing = false
    private var renaming = false

    /// Medication's fields come back changed: only its first one.
    var renamed: Bool {
        get { lock.withLock { renaming } }
        set { lock.withLock { renaming = newValue } }
    }

    var failSummary: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    func record(_ s: String) { lock.withLock { log.append(s) } }
    func recordDay(_ d: LocalDay) { lock.withLock { days.append(d) } }
    func count(_ prefix: String) -> Int { lock.withLock { log.filter { $0.hasPrefix(prefix) }.count } }
    var all: [String] { lock.withLock { log } }
    var lastDay: LocalDay? { lock.withLock { days.last } }
}

/// Counts calls across tasks.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}

/// Holds one call until the test opens it, and tells the test when it is held.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var watcher: CheckedContinuation<Void, Never>?
    private var held = false
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let (resumeNow, watcher): (Bool, CheckedContinuation<Void, Never>?) = lock.withLock {
                held = true
                if isOpen { return (true, nil) }
                waiter = c
                defer { self.watcher = nil }
                return (false, self.watcher)
            }
            watcher?.resume()
            if resumeNow { c.resume() }
        }
    }

    func arrived() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let already: Bool = lock.withLock {
                if held { return true }
                watcher = c
                return false
            }
            if already { c.resume() }
        }
    }

    func open() {
        let w: CheckedContinuation<Void, Never>? = lock.withLock {
            isOpen = true
            defer { waiter = nil }
            return waiter
        }
        w?.resume()
    }
}

/// A clock a test can move.
@MainActor
private final class Clock {
    var now = Fixed.now
}

@MainActor
final class HomeModelTests: XCTestCase {
    private var calls = Calls()
    private var clock = Clock()
    private var failSummary: Bool {
        get { calls.failSummary }
        set { calls.failSummary = newValue }
    }

    private func model(attention: [AttentionItem] = [Fixed.unrecorded, Fixed.gap],
                       comingUp: [ReceiverEntryItem] = [Fixed.upcoming],
                       trackers: [TrackerItem] = [Fixed.tracker("medication", .active)],
                       items: [DayItem] = [Fixed.logged]) -> HomeModel {
        let calls = calls
        let home = HomeService(
            needsAttention: { id, limit in
                calls.record("attention:\(id):\(limit ?? -1)")
                if calls.failSummary { throw URLError(.notConnectedToInternet) }
                return attention
            },
            comingUp: { id, limit in
                calls.record("comingUp:\(id):\(limit ?? -1)")
                return comingUp
            },
            dayTimeline: { id, day in
                calls.record("day:\(id):\(day.dayString)")
                calls.recordDay(day)
                return DayTimeline(day: day, items: items)
            },
            entry: { _ in throw URLError(.badURL) },
            journalNote: { _ in throw URLError(.badURL) }
        )
        var trackersService = TrackersFixtures.service()
        trackersService.listTrackers = { id in
            calls.record("trackers:\(id)")
            return trackers
        }
        trackersService.trackerDetail = { id in
            calls.record("detail:\(id)")
            guard id == "medication" else { throw URLError(.badURL) }
            if calls.renamed {
                let m = TrackersFixtures.medication
                return TrackerProfile(id: m.id, name: m.name, icon: m.icon, color: m.color, status: m.status,
                                      pausedAt: m.pausedAt, fields: Array(m.fields.prefix(1)),
                                      gapHours: m.gapHours, scheduleCount: m.scheduleCount,
                                      lastLoggedAt: m.lastLoggedAt, attention: m.attention)
            }
            return TrackersFixtures.medication
        }
        let clock = clock
        return HomeModel(home: home, trackers: trackersService, clock: { clock.now })
    }

    // MARK: Which sections show

    func testNeedsAttentionAndComingUpLoadAtMostThreeForTheReceiver() async {
        let model = model()
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.status, .needsAttention([Fixed.unrecorded, Fixed.gap]))
        XCTAssertTrue(model.showsComingUp)
        XCTAssertEqual(model.comingUp, [Fixed.upcoming])
        XCTAssertEqual(calls.count("attention:eleanor:3"), 1)
        XCTAssertEqual(calls.count("comingUp:eleanor:3"), 1)
        XCTAssertEqual(calls.count("trackers:eleanor"), 1)
    }

    func testComingUpIsAbsentWhenNothingIsScheduled() async {
        let model = model(comingUp: [])
        await model.show(Fixed.eleanor)
        XCTAssertFalse(model.showsComingUp)
    }

    func testNothingNeedingAttentionIsTheAllClearState() async {
        let model = model(attention: [])
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.status, .allClear)
    }

    func testNoActiveTrackersOutranksAllClear() async {
        let allPaused = model(attention: [], trackers: [Fixed.tracker("walk", .paused)])
        await allPaused.show(Fixed.eleanor)
        XCTAssertEqual(allPaused.status, .noActiveTrackers)

        let none = model(attention: [], trackers: [])
        await none.show(Fixed.eleanor)
        XCTAssertEqual(none.status, .noActiveTrackers)
    }

    func testAnEmptyDayOffersALogAndANote() async {
        let model = model(items: [])
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.dayPhase, .loaded([]))
        XCTAssertEqual(model.dayOffers, [.logAnEntry, .writeANote])
    }

    func testAnEmptyDayWithNoActiveTrackersOffersOnlyANote() async {
        let model = model(attention: [], trackers: [Fixed.tracker("walk", .paused)], items: [])
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.dayOffers, [.writeANote])
    }

    func testADayWithItemsOffersNothing() async {
        let model = model()
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.dayOffers, [])
    }

    func testTheTimelinesTrackersFieldsAreReadOnce() async {
        let model = model()
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.fields["medication"], TrackersFixtures.medication.fields)
        await model.stepBack()
        XCTAssertEqual(calls.count("detail:medication"), 1)
    }

    func testRefreshingReadsTheFieldsAfreshSoChangesShow() async {
        let model = model()
        await model.show(Fixed.eleanor)
        calls.renamed = true
        await model.refresh()
        XCTAssertEqual(calls.count("detail:medication"), 2)
        XCTAssertEqual(model.fields["medication"], Array(TrackersFixtures.medication.fields.prefix(1)))
        await model.stepBack()
        XCTAssertEqual(calls.count("detail:medication"), 2, "stepping days keeps this refresh's fields")
        await model.show(Fixed.eleanor)
        XCTAssertEqual(calls.count("detail:medication"), 3, "coming back to Home is a refresh too")
    }

    func testAnOlderRefreshLandingLateDoesNotOverwriteANewerOne() async {
        let gate = Gate()
        let counter = Counter()
        let home = HomeService(
            needsAttention: { _, _ in
                let n = counter.next()
                if n == 2 { await gate.wait() }
                return n == 2 ? [Fixed.gap] : [Fixed.unrecorded]
            },
            comingUp: { _, _ in [] },
            dayTimeline: { _, day in DayTimeline(day: day, items: []) },
            entry: { _ in throw URLError(.badURL) },
            journalNote: { _ in throw URLError(.badURL) }
        )
        var trackers = TrackersFixtures.service()
        trackers.listTrackers = { _ in [Fixed.tracker("medication", .active)] }
        let clock = clock
        let model = HomeModel(home: home, trackers: trackers, clock: { clock.now })
        await model.show(Fixed.eleanor)

        let older = Task { await model.refresh() }
        await gate.arrived()
        await model.refresh()
        XCTAssertEqual(model.attention, [Fixed.unrecorded])
        gate.open()
        await older.value
        XCTAssertEqual(model.attention, [Fixed.unrecorded], "the older refresh's answer is discarded")
    }

    // MARK: The day

    func testTheDayStartsOnTodayInTheReceiversZone() async {
        let model = model()
        await model.show(Fixed.eleanor)
        // Nov 8 in UTC, but still Nov 7 in Chicago.
        XCTAssertEqual(model.day, Fixed.nov7)
        XCTAssertEqual(calls.lastDay, Fixed.nov7)
        XCTAssertTrue(model.isShowingToday)
        XCTAssertFalse(model.showsTodayButton)
        XCTAssertFalse(model.canStepForward)
    }

    func testSteppingStopsAtToday() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.stepForward()
        XCTAssertEqual(model.day, Fixed.nov7)

        await model.stepBack()
        XCTAssertEqual(model.day, LocalDay(year: 2026, month: 11, day: 6))
        XCTAssertEqual(calls.lastDay, LocalDay(year: 2026, month: 11, day: 6))
        XCTAssertTrue(model.showsTodayButton)
        XCTAssertTrue(model.canStepForward)

        await model.stepForward()
        XCTAssertEqual(model.day, Fixed.nov7)
        XCTAssertFalse(model.canStepForward)
        XCTAssertFalse(model.showsTodayButton)
    }

    func testTodayReturnsInOneTap() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        await model.stepBack()
        await model.stepBack()
        await model.goToToday()
        XCTAssertEqual(model.day, Fixed.nov7)
        XCTAssertFalse(model.showsTodayButton)
    }

    func testJumpingToADayShowsItAndADayAheadIsRefused() async {
        let model = model()
        await model.show(Fixed.eleanor)
        let oct3 = LocalDay(year: 2026, month: 10, day: 3)
        await model.jump(to: oct3)
        XCTAssertEqual(model.day, oct3)
        XCTAssertEqual(calls.lastDay, oct3)

        await model.jump(to: LocalDay(year: 2026, month: 11, day: 8))
        XCTAssertEqual(model.day, oct3)
    }

    // MARK: Receivers and refresh

    func testSwitchingReceiversReloadsEverythingAndResetsTheDay() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        await model.stepBack()

        await model.show(Fixed.walter)
        XCTAssertEqual(model.receiver, Fixed.walter)
        XCTAssertEqual(model.day, LocalDay(Fixed.now, zone: Fixed.denver))
        XCTAssertEqual(calls.count("attention:walter"), 1)
        XCTAssertEqual(calls.count("comingUp:walter"), 1)
        XCTAssertEqual(calls.count("trackers:walter"), 1)
        XCTAssertEqual(calls.count("day:walter:2026-11-07"), 1)
    }

    func testTheSameReceiverAgainRefreshesInPlaceOnTheDayShowing() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.day, LocalDay(year: 2026, month: 11, day: 6))
        XCTAssertEqual(calls.count("attention:eleanor"), 2)
    }

    // MARK: Back from Quick log

    func testALoggingRunReturnsToTheDayItLoggedReadAfresh() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        await model.reflect(QuickLogModel.Outcome(receiverID: "eleanor", planning: false, latestDay: Fixed.nov7, savedAny: true))
        XCTAssertEqual(model.day, Fixed.nov7)
        XCTAssertEqual(calls.lastDay, Fixed.nov7)
        XCTAssertEqual(calls.count("attention:eleanor"), 2)
        XCTAssertEqual(calls.count("comingUp:eleanor"), 2)
    }

    func testAPlanningRunReadsHomeAfreshOnTheDayShowing() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        let nov6 = LocalDay(year: 2026, month: 11, day: 6)
        await model.reflect(QuickLogModel.Outcome(receiverID: "eleanor", planning: true, latestDay: LocalDay(year: 2026, month: 11, day: 9),
                                                  savedAny: true))
        XCTAssertEqual(model.day, nov6)
        XCTAssertEqual(calls.count("comingUp:eleanor"), 2)
        XCTAssertEqual(calls.lastDay, nov6)
    }

    func testARunThatSavedNothingReadsNothing() async {
        let model = model()
        await model.show(Fixed.eleanor)
        await model.reflect(QuickLogModel.Outcome(receiverID: "eleanor", planning: false, latestDay: nil, savedAny: false))
        XCTAssertEqual(calls.count("attention:eleanor"), 1)
    }

    func testRefreshReloadsTheWholeScreen() async {
        let model = model()
        await model.show(Fixed.eleanor)
        clock.now = Fixed.now.addingTimeInterval(600)
        await model.refresh()
        XCTAssertEqual(calls.count("attention:eleanor"), 2)
        XCTAssertEqual(calls.count("comingUp:eleanor"), 2)
        XCTAssertEqual(calls.count("trackers:eleanor"), 2)
        XCTAssertEqual(calls.count("day:eleanor"), 2)
        XCTAssertEqual(model.now, Fixed.now.addingTimeInterval(600))
    }

    func testAFailedRefreshKeepsWhatWasShowing() async {
        let model = model()
        await model.show(Fixed.eleanor)
        failSummary = true
        await model.refresh()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.refreshFailed)
        XCTAssertEqual(model.status, .needsAttention([Fixed.unrecorded, Fixed.gap]))
    }

    func testAFailedFirstLoadFails() async {
        failSummary = true
        let model = model()
        await model.show(Fixed.eleanor)
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
        XCTAssertNil(model.status)
    }

    // MARK: Where things lead

    func testEachKindOfAttentionLeadsWhereThePRDSays() {
        let r = Fixed.eleanor
        XCTAssertEqual(HomeV1View.route(for: Fixed.unrecorded, receiver: r), .entry(id: "e1", receiver: r))
        let high = AttentionItem(tracker: Fixed.medication, attention: .outOfRange(
            entryID: "e2", fieldID: "sys", fieldLabel: "Systolic", unit: "mmHg", value: 152,
            range: ValueRangeInfo(low: 90, high: 140)))
        XCTAssertEqual(HomeV1View.route(for: high, receiver: r), .entry(id: "e2", receiver: r))
        XCTAssertEqual(HomeV1View.route(for: Fixed.gap, receiver: r), .tracker(id: "meals", receiver: r))
    }

    func testTimelineItemsLeadToTheirEntryOrNote() {
        let r = Fixed.eleanor
        XCTAssertEqual(HomeV1View.route(for: Fixed.logged, receiver: r), .entry(id: "logged", receiver: r))
        XCTAssertEqual(HomeV1View.route(for: .note(HomeFixtures.afternoonNote), receiver: r),
                       .journalNote(id: "note-yesterday", receiver: r))
    }

    func testTrackersOpensOnActiveUnlessHomeChoseNeedsAttention() {
        let r = Fixed.eleanor
        XCTAssertEqual(V1Route.trackers(r), .trackers(r, filter: .active))
        let opened = TrackersListModel(receiver: r, service: TrackersFixtures.service(), filter: .needsAttention)
        XCTAssertEqual(opened.filter, .needsAttention)
        XCTAssertEqual(TrackersListModel(receiver: r, service: TrackersFixtures.service()).filter, .active)
    }

    func testPoppingToTrackersStillFindsAFilteredList() {
        let r = Fixed.eleanor
        let path: [V1Route] = [.trackers(r, filter: .needsAttention), .tracker(id: "t", receiver: r)]
        XCTAssertEqual(V1Route.poppedToTrackers(path), [.trackers(r, filter: .needsAttention)])
    }
}

// MARK: - Jump to day

final class JumpToDayModelTests: XCTestCase {
    private let today = LocalDay(year: 2026, month: 11, day: 7)

    func testOpensOnTheDayShowingInItsMonth() {
        let model = JumpToDayModel(today: today, showing: LocalDay(year: 2026, month: 10, day: 23))
        XCTAssertEqual(model.selected, LocalDay(year: 2026, month: 10, day: 23))
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 10))
        XCTAssertTrue(model.canGoForward)
    }

    func testPickingADaySelectsItAndADayAheadIsRefused() {
        var model = JumpToDayModel(today: today, showing: today)
        model.pick(LocalDay(year: 2026, month: 11, day: 2))
        XCTAssertEqual(model.selected, LocalDay(year: 2026, month: 11, day: 2))
        XCTAssertEqual(model.state(of: LocalDay(year: 2026, month: 11, day: 2)), .single)
        XCTAssertEqual(model.state(of: today), .today)

        model.pick(LocalDay(year: 2026, month: 11, day: 8))
        XCTAssertEqual(model.selected, LocalDay(year: 2026, month: 11, day: 2))
        XCTAssertTrue(model.isDisabled(LocalDay(year: 2026, month: 11, day: 8)))
        XCTAssertEqual(model.state(of: LocalDay(year: 2026, month: 11, day: 8)), .disabled)
    }

    func testTheCalendarStopsAtThisMonth() {
        var model = JumpToDayModel(today: today, showing: today)
        XCTAssertFalse(model.canGoForward)
        model.goForward()
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 11))
        model.goBack()
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 10))
        model.goForward()
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 11))
    }
}

// MARK: - What Home says

final class HomeTextTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Chicago")!
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T18:00:00Z")! // Sun Nov 8, noon in Chicago

    func testAttentionCauses() {
        let at = ISO8601DateFormatter().date(from: "2026-11-08T14:00:00Z")! // 8:00 AM
        XCTAssertEqual(HomeText.attention(.unrecorded(entryID: "e", occurrenceAt: at), now: now, zone: zone),
                       "Unrecorded · Today at 8:00 AM")
        XCTAssertEqual(HomeText.attention(.outOfRange(entryID: "e", fieldID: "sys", fieldLabel: "Systolic",
                                                      unit: "mmHg", value: 168,
                                                      range: ValueRangeInfo(low: 90, high: 140)),
                                          now: now, zone: zone),
                       "Systolic 168 · expected 90–140")
        XCTAssertEqual(HomeText.attention(.gap(since: now.addingTimeInterval(-72 * 3600), gapHours: 24),
                                          now: now, zone: zone),
                       "Nothing logged in 3 days")
        XCTAssertEqual(HomeText.attention(.gap(since: now.addingTimeInterval(-30 * 3600), gapHours: 24),
                                          now: now, zone: zone),
                       "Nothing logged in 30 hours")
    }

    func testComingUpSaysTheScheduleAndWhen() {
        func entry(_ iso: String, _ schedule: String?) -> TrackerEntry {
            TrackerEntry(id: "x", state: .scheduled, at: ISO8601DateFormatter().date(from: iso)!, values: [:],
                         note: nil, byName: nil, scheduleName: schedule)
        }
        XCTAssertEqual(HomeText.comingUp(entry("2026-11-09T02:00:00Z", "Evening"), now: now, zone: zone),
                       "Evening · Today at 8:00 PM")
        XCTAssertEqual(HomeText.comingUp(entry("2026-11-09T20:00:00Z", nil), now: now, zone: zone),
                       "Tomorrow at 2:00 PM")
        XCTAssertEqual(HomeText.comingUp(entry("2026-11-11T16:00:00Z", nil), now: now, zone: zone),
                       "Wednesday at 10:00 AM")
        XCTAssertEqual(HomeText.comingUp(entry("2026-11-24T15:00:00Z", nil), now: now, zone: zone),
                       "Nov 24 at 9:00 AM")
    }

    func testTheDayIsTodayOrItsWeekday() {
        let today = LocalDay(year: 2026, month: 10, day: 25)
        XCTAssertTrue(HomeText.dayTitle(today, today: today) == ("Today", "Sun, Oct 25"))
        XCTAssertTrue(HomeText.dayTitle(LocalDay(year: 2026, month: 10, day: 23), today: today) == ("Friday", "Oct 23"))
        XCTAssertTrue(HomeText.dayTitle(LocalDay(year: 2025, month: 12, day: 31), today: today)
                      == ("Wednesday", "Dec 31, 2025"))
    }

    func testOnlyALoggedNumberOutsideItsRangeIsMarked() {
        let field = TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg",
                                     range: ValueRangeInfo(low: 90, high: 140), options: [])
        func entry(_ state: EntryState, _ n: Double) -> TrackerEntry {
            TrackerEntry(id: "x", state: state, at: now, values: ["sys": .number(n)], note: nil, byName: nil)
        }
        XCTAssertTrue(HomeText.isOutOfRange(entry(.logged, 168), field: field))
        XCTAssertFalse(HomeText.isOutOfRange(entry(.logged, 120), field: field))
        XCTAssertFalse(HomeText.isOutOfRange(entry(.skipped, 168), field: field))
    }
}
