import XCTest
@testable import Caregiver

/// Fixed instants and zones throughout: nothing here reads the clock or the device zone.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Sat Nov 7 2026, 6:00 PM in Chicago.
    static let now = at("2026-11-08T00:00:00Z")

    static let medication = TrackerBadgeInfo(id: "medication", name: "Medication", icon: "pills", color: "#6f5fe0")
    static let bp = TrackerBadgeInfo(id: "bp", name: "Blood pressure", icon: "heart", color: "#1c8fe0")

    static let medicationFields = [
        TrackerFieldInfo(id: "dose", label: "Dose", kind: .choice, unit: nil,
                         options: [ChoiceOptionInfo(id: "lis10", label: "Lisinopril 10 mg", retired: false)]),
        TrackerFieldInfo(id: "given", label: "Given", kind: .boolean, unit: nil, options: []),
        TrackerFieldInfo(id: "mood", label: "Mood", kind: .text, unit: nil, paused: true, options: []),
    ]

    static let bpFields = [
        TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg",
                         range: ValueRangeInfo(low: 90, high: 140), options: []),
        TrackerFieldInfo(id: "dia", label: "Diastolic", kind: .number, unit: "mmHg",
                         range: ValueRangeInfo(low: 60, high: 90), options: []),
    ]

    static func detail(_ state: EntryState, at: Date, values: [String: EntryValue] = [:],
                       tracker: TrackerBadgeInfo = medication, fields: [TrackerFieldInfo] = medicationFields,
                       note: String? = nil, byName: String? = nil, schedule: String? = nil,
                       settledAt: Date? = nil, updatedByName: String? = nil, updatedAt: Date? = nil,
                       outOfRange: [OutOfRangeInfo] = []) -> EntryDetailInfo {
        EntryDetailInfo(
            entry: TrackerEntry(id: "e1", state: state, at: at, values: values, note: note, byName: byName,
                                scheduleName: schedule),
            tracker: tracker, fields: fields, planned: schedule != nil, occurrenceAt: schedule != nil ? at : nil,
            unrecordedAlert: nil, settledAt: settledAt, updatedByName: updatedByName, updatedAt: updatedAt,
            outOfRange: outOfRange)
    }
}

final class EntryDetailContentTests: XCTestCase {
    private func content(_ d: EntryDetailInfo) -> EntryDetailContent {
        EntryDetailContent(d, now: Fixed.now, zone: Fixed.chicago)
    }

    func testOffersFollowTheStateNotWhereItWasOpenedFrom() {
        XCTAssertEqual(EntryOffer.offers(for: .scheduled), [.logIt, .skip])
        XCTAssertEqual(EntryOffer.offers(for: .unrecorded), [.logIt, .skip])
        XCTAssertEqual(EntryOffer.offers(for: .logged), [.edit, .delete])
        XCTAssertEqual(EntryOffer.offers(for: .skipped), [.edit, .delete])
    }

    func testScheduledShowsWhatIsPreFilledAndWhatIsLeftAndItsSchedule() {
        // Tonight at 8:00 PM Chicago.
        let c = content(Fixed.detail(.scheduled, at: Fixed.at("2026-11-08T02:00:00Z"),
                                     values: ["dose": .list(["lis10"])], schedule: "Evening"))
        XCTAssertEqual(c.when, "Today at 8:00 PM")
        XCTAssertNil(c.callout)
        XCTAssertEqual(c.fieldsTitle, "PRE-FILLED")
        XCTAssertEqual(c.fields, [
            DetailRow(label: "Dose", value: "Lisinopril 10 mg"),
            // Mood is paused, so nobody will be asked for it; it is not "left".
            DetailRow(label: "Given", value: HomeText.leftForLogger, pending: true),
        ])
        XCTAssertEqual(c.details, [DetailRow(label: "Schedule", value: "Evening")])
    }

    func testScheduledWithNothingPreFilledHasNoFieldsSection() {
        let c = content(Fixed.detail(.scheduled, at: Fixed.at("2026-11-08T15:00:00Z"), schedule: "Morning"))
        XCTAssertNil(c.fieldsTitle)
        XCTAssertTrue(c.fields.isEmpty)
        XCTAssertEqual(c.when, "Tomorrow at 9:00 AM")
    }

    func testUnrecordedCallsForAttentionOnlyWhileItIsInNeedsAttention() {
        let recent = content(Fixed.detail(.unrecorded, at: Fixed.at("2026-11-07T14:00:00Z"), schedule: "Morning"))
        XCTAssertEqual(recent.callout, .unrecorded)
        XCTAssertEqual(recent.offers, [.logIt, .skip])

        // Forty-eight hours on it has left needs attention, so it no longer claims to need it.
        let old = content(Fixed.detail(.unrecorded, at: Fixed.at("2026-11-05T23:00:00Z"), schedule: "Morning"))
        XCTAssertNil(old.callout)
    }

    func testOutOfRangeNamesTheValueAndTheRangeItWasExpectedToHoldTo() {
        let c = content(Fixed.detail(
            .logged, at: Fixed.at("2026-11-07T14:04:00Z"), values: ["sys": .number(168), "dia": .number(94)],
            tracker: Fixed.bp, fields: Fixed.bpFields, note: "Felt a little dizzy after breakfast.",
            byName: "Trevor", settledAt: Fixed.at("2026-11-07T14:05:00Z"),
            outOfRange: [OutOfRangeInfo(fieldID: "sys", value: 168, range: ValueRangeInfo(low: 90, high: 140))]))
        XCTAssertEqual(c.callout, .outOfRange(["Systolic is 168 mmHg. It is expected to stay between 90 and 140."]))
        XCTAssertEqual(c.fieldsTitle, "FIELDS")
        XCTAssertEqual(c.fields, [
            DetailRow(label: "Systolic", value: "168 mmHg", expected: "Expected 90–140"),
            DetailRow(label: "Diastolic", value: "94 mmHg"),
        ])
        XCTAssertEqual(c.note, "Felt a little dizzy after breakfast.")
        XCTAssertEqual(c.when, "Today at 8:04 AM")
    }

    func testChangedByShowsOnlyOnceChanged() {
        let base = Fixed.detail(.logged, at: Fixed.at("2026-11-07T14:04:00Z"), values: ["sys": .number(120)],
                                tracker: Fixed.bp, fields: Fixed.bpFields, byName: "Trevor",
                                settledAt: Fixed.at("2026-11-07T14:05:00Z"))
        XCTAssertEqual(content(base).details, [DetailRow(label: "Logged by", value: "Trevor · 8:05 AM")])

        let changed = Fixed.detail(.logged, at: Fixed.at("2026-11-07T14:04:00Z"), values: ["sys": .number(120)],
                                   tracker: Fixed.bp, fields: Fixed.bpFields, byName: "Trevor",
                                   settledAt: Fixed.at("2026-11-07T14:05:00Z"),
                                   updatedByName: "Dana", updatedAt: Fixed.at("2026-11-07T15:10:00Z"))
        XCTAssertEqual(content(changed).details, [
            DetailRow(label: "Logged by", value: "Trevor · 8:05 AM"),
            DetailRow(label: "Changed by", value: "Dana · 9:10 AM"),
        ])
    }

    func testScheduleLineOnlyWhenItCameFromOne() {
        let adHoc = content(Fixed.detail(.logged, at: Fixed.at("2026-11-07T14:04:00Z"),
                                         values: ["given": .bool(true)], byName: "Dana"))
        XCTAssertFalse(adHoc.details.contains { $0.label == "Schedule" })

        let planned = content(Fixed.detail(.logged, at: Fixed.at("2026-11-07T14:04:00Z"),
                                           values: ["given": .bool(true)], byName: "Dana", schedule: "Morning"))
        XCTAssertEqual(planned.details.first, DetailRow(label: "Schedule", value: "Morning"))
    }

    func testPausedFieldsKeepTheirValues() {
        let c = content(Fixed.detail(.logged, at: Fixed.at("2026-11-07T14:04:00Z"),
                                     values: ["given": .bool(true), "mood": .string("Cheerful")], byName: "Dana"))
        XCTAssertEqual(c.fields, [
            DetailRow(label: "Given", value: "Yes"),
            DetailRow(label: "Mood", value: "Cheerful"),
        ])
    }

    func testSkippedSaysWhoSkippedItAndWhenOnAnotherDay() {
        // Skipped Thursday's lunch on Friday.
        let c = content(Fixed.detail(.skipped, at: Fixed.at("2026-11-05T18:30:00Z"), note: "Ate a big late breakfast.",
                                     byName: "Dana", schedule: "Lunch", settledAt: Fixed.at("2026-11-06T14:00:00Z")))
        XCTAssertNil(c.callout)
        XCTAssertNil(c.fieldsTitle)
        XCTAssertEqual(c.details, [
            DetailRow(label: "Schedule", value: "Lunch"),
            DetailRow(label: "Skipped by", value: "Dana · Yesterday at 8:00 AM"),
        ])
        XCTAssertEqual(c.offers, [.edit, .delete])
    }

    func testOutOfRangeSentenceForOneSidedRanges() {
        XCTAssertEqual(HomeText.outOfRangeSentence(label: "Weight", value: 150.5, unit: "lb",
                                                   range: ValueRangeInfo(low: nil, high: 140)),
                       "Weight is 150.5 lb. It is expected to stay at or below 140.")
        XCTAssertEqual(HomeText.outOfRangeSentence(label: "Pulse", value: 48, unit: nil,
                                                   range: ValueRangeInfo(low: 50, high: nil)),
                       "Pulse is 48. It is expected to stay at or above 50.")
        XCTAssertEqual(HomeText.expectedUnderValue(ValueRangeInfo(low: nil, high: 140)), "Expected at most 140")
    }
}

final class JournalNoteContentTests: XCTestCase {
    private func note(updatedBy: String?, updatedAt: Date?) -> JournalNoteInfo {
        JournalNoteInfo(id: "n1", receiverID: "eleanor", at: Fixed.at("2026-11-07T15:30:00Z"),
                        body: "Rough morning.", authorName: "Dana", createdAt: Fixed.at("2026-11-07T15:32:00Z"),
                        updatedByName: updatedBy, updatedAt: updatedAt)
    }

    func testWrittenByAlwaysChangedByOnlyOnceChanged() {
        let plain = JournalNoteContent(note(updatedBy: nil, updatedAt: nil), now: Fixed.now, zone: Fixed.chicago)
        XCTAssertEqual(plain.when, "Today at 9:30 AM")
        XCTAssertEqual(plain.details, [DetailRow(label: "Written by", value: "Dana · 9:32 AM")])

        let changed = JournalNoteContent(note(updatedBy: "Dana", updatedAt: Fixed.at("2026-11-07T16:05:00Z")),
                                         now: Fixed.now, zone: Fixed.chicago)
        XCTAssertEqual(changed.details.last, DetailRow(label: "Changed by", value: "Dana · 10:05 AM"))
    }
}

/// Answers a scripted list, one per call.
private final class Script<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<Value, Error>]
    private(set) var limits: [Int?] = []

    init(_ answers: [Result<Value, Error>]) { self.answers = answers }

    func next(limit: Int? = nil) throws -> Value {
        try lock.withLock {
            limits.append(limit)
            return try answers.removeFirst().get()
        }
    }
}

@MainActor
final class HomeReadModelTests: XCTestCase {
    private struct Offline: Error {}

    private static let item = ReceiverEntryItem(tracker: Fixed.medication, entry: TrackerEntry(
        id: "next", state: .scheduled, at: Fixed.at("2026-11-08T14:00:00Z"), values: [:], note: nil, byName: nil,
        scheduleName: "Morning"))

    private func home(comingUp script: Script<[ReceiverEntryItem]>) -> HomeService {
        HomeService(needsAttention: { _, _ in [] },
                    comingUp: { _, limit in try script.next(limit: limit) },
                    dayTimeline: { _, day in DayTimeline(day: day, items: []) },
                    entry: { _ in throw Offline() },
                    journalNote: { _ in throw Offline() })
    }

    func testComingUpAsksForTheWholeList() async {
        let script = Script<[ReceiverEntryItem]>([.success([Self.item])])
        let model = HomeReadModel.comingUp("eleanor", home: home(comingUp: script))
        await model.load()
        XCTAssertEqual(model.phase, .loaded([Self.item]))
        XCTAssertEqual(script.limits, [nil])
    }

    func testComingUpEmptiedWhileLookingStaysAndSaysSo() async {
        let script = Script<[ReceiverEntryItem]>([.success([Self.item]), .success([])])
        let model = HomeReadModel.comingUp("eleanor", home: home(comingUp: script))
        await model.load()
        await model.load()
        XCTAssertEqual(model.phase, .loaded([]))
    }

    func testARefreshThatFailsKeepsWhatWasShowing() async {
        let script = Script<[ReceiverEntryItem]>([.success([Self.item]), .failure(Offline())])
        let model = HomeReadModel.comingUp("eleanor", home: home(comingUp: script))
        await model.load()
        await model.load()
        XCTAssertEqual(model.phase, .loaded([Self.item]))
        XCTAssertTrue(model.refreshFailed)
    }

    func testAFirstLoadThatFailsOffersARetry() async {
        let script = Script<[ReceiverEntryItem]>([.failure(Offline()), .success([Self.item])])
        let model = HomeReadModel.comingUp("eleanor", home: home(comingUp: script))
        await model.load()
        XCTAssertEqual(model.phase, .failed(.unknown))
        await model.retry()
        XCTAssertEqual(model.phase, .loaded([Self.item]))
    }

    func testAnEntryDeletedElsewhereIsGoneEvenAfterLoading() async {
        let detail = Fixed.detail(.logged, at: Fixed.now, values: ["given": .bool(true)], byName: "Dana")
        let script = Script<EntryDetailInfo>([.success(detail), .failure(AppError.forStatus(404, serverMessage: nil))])
        let service = HomeService(needsAttention: { _, _ in [] }, comingUp: { _, _ in [] },
                                  dayTimeline: { _, day in DayTimeline(day: day, items: []) },
                                  entry: { _ in try script.next() },
                                  journalNote: { _ in throw Offline() })
        let model = HomeReadModel.entry("e1", home: service)
        await model.load()
        XCTAssertEqual(model.value, detail)
        await model.load()
        XCTAssertEqual(model.phase, .gone)
    }
}
