import XCTest
@testable import Caregiver

/// Fixed instants and zones throughout: nothing here reads the clock or the device zone.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Nov 8 05:30 UTC — still Saturday Nov 7 in Chicago.
    static let now = at("2026-11-08T05:30:00Z")
    static let nov6 = LocalDay(year: 2026, month: 11, day: 6)
    static let nov7 = LocalDay(year: 2026, month: 11, day: 7)

    static let eleanor = TeamReceiver(id: "eleanor", name: "Eleanor", timeZone: chicago)

    static let bp = TrackerBadgeInfo(id: "bp", name: "Blood pressure", icon: "heart", color: "#1c8fe0")

    static let fields = [
        TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", required: true,
                         range: ValueRangeInfo(low: 90, high: 140), options: []),
        TrackerFieldInfo(id: "dia", label: "Diastolic", kind: .number, unit: "mmHg", required: true, options: []),
        TrackerFieldInfo(id: "pos", label: "Position", kind: .choice, unit: nil,
                         options: [ChoiceOptionInfo(id: "sit", label: "Sitting", retired: false),
                                   ChoiceOptionInfo(id: "lie", label: "Lying", retired: true)]),
        TrackerFieldInfo(id: "arm", label: "Arm", kind: .text, unit: nil, paused: true, options: []),
    ]

    /// Logged ad hoc Nov 7 at 5 PM Chicago (23:00 UTC), systolic out of range; diastolic
    /// was made required after it was logged, so it never answered it.
    static func logged(planned: Bool = false, schedule: String? = nil) -> EntryDetailInfo {
        EntryDetailInfo(
            entry: TrackerEntry(id: "e1", state: .logged, at: at("2026-11-07T23:00:00Z"),
                                values: ["sys": .number(152), "pos": .list(["lie"]), "arm": .string("Left")],
                                note: "Felt dizzy", byName: "Dana", scheduleName: schedule),
            tracker: bp, fields: fields, planned: planned,
            occurrenceAt: planned ? at("2026-11-07T23:00:00Z") : nil, unrecordedAlert: planned ? false : nil,
            settledAt: at("2026-11-07T23:05:00Z"), updatedByName: nil, updatedAt: nil,
            outOfRange: [OutOfRangeInfo(fieldID: "sys", value: 152, range: ValueRangeInfo(low: 90, high: 140))])
    }

    /// Skipped, its time still ahead.
    static let skippedAhead = EntryDetailInfo(
        entry: TrackerEntry(id: "e2", state: .skipped, at: at("2026-11-08T14:00:00Z"), values: [:],
                            note: "Out at the doctor", byName: "Marcus", scheduleName: "Morning"),
        tracker: bp, fields: fields, planned: true, occurrenceAt: at("2026-11-08T14:00:00Z"),
        unrecordedAlert: false, settledAt: at("2026-11-08T05:00:00Z"), updatedByName: nil, updatedAt: nil,
        outOfRange: [])

    static func saved(_ d: EntryDetailInfo, at: Date) -> EntryDetailInfo {
        EntryDetailInfo(entry: TrackerEntry(id: d.entry.id, state: .logged, at: at, values: d.entry.values,
                                            note: d.entry.note, byName: "Trevor",
                                            scheduleName: d.entry.scheduleName),
                        tracker: d.tracker, fields: d.fields, planned: d.planned, occurrenceAt: d.occurrenceAt,
                        unrecordedAlert: d.unrecordedAlert, settledAt: d.settledAt, updatedByName: "Trevor",
                        updatedAt: now, outOfRange: [])
    }

    static let note = JournalNoteInfo(id: "n1", receiverID: "eleanor", at: at("2026-11-07T20:00:00Z"),
                                      body: "Rough morning.", authorName: "Dana",
                                      createdAt: at("2026-11-07T20:02:00Z"), updatedByName: nil, updatedAt: nil)

    static func home() -> HomeService {
        HomeService(needsAttention: { _, _ in [] }, comingUp: { _, _ in [] },
                    dayTimeline: { _, day in DayTimeline(day: day, items: []) },
                    entry: { _ in throw URLError(.badURL) }, journalNote: { _ in throw URLError(.badURL) })
    }
}

/// What a write was sent, across tasks.
private final class Sent<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ t: T) { lock.withLock { items.append(t) } }
    var all: [T] { lock.withLock { items } }
}

@MainActor
final class EditEntryModelTests: XCTestCase {
    private func model(_ detail: EntryDetailInfo = Fixed.logged(),
                       change: @escaping @Sendable (String, EntryCareWrite) async throws -> EntryDetailInfo
                           = { _, _ in throw URLError(.badURL) }) -> EditEntryModel {
        var home = Fixed.home()
        home.changeEntry = change
        return EditEntryModel(detail, zone: Fixed.chicago, home: home, clock: { Fixed.now })
    }

    func testOpensOnTheEntryAsLogged() {
        let m = model()
        XCTAssertEqual(m.occurredAt, Fixed.at("2026-11-07T23:00:00Z"))
        XCTAssertEqual(m.note, "Felt dizzy")
        XCTAssertEqual(m.values.numberText(for: "sys"), "152")
        XCTAssertEqual(m.activeFields.map(\.id), ["sys", "dia", "pos"])
        XCTAssertEqual(m.hints, ["sys": "Expected 90–140"])
        XCTAssertFalse(m.logsTheCare)
    }

    func testALoggedEntryNeedNotAnswerARequiredFieldItNeverAnswered() {
        let m = model()
        XCTAssertEqual(m.problems, [])
        m.values.setNumberText("", for: "sys")
        XCTAssertEqual(m.problems, ["Systolic is required."])
    }

    func testEditingASkipLogsItSoEveryRequiredFieldMustBeAnswered() {
        let m = model(Fixed.skippedAhead)
        XCTAssertTrue(m.logsTheCare)
        XCTAssertEqual(m.problems, ["Systolic is required.", "Diastolic is required."])
        m.values.setNumberText("120", for: "sys")
        m.values.setNumberText("80", for: "dia")
        XCTAssertEqual(m.problems, [])
    }

    func testASkipAheadOfItsTimeStartsAtNow() {
        XCTAssertEqual(model(Fixed.skippedAhead).occurredAt, Fixed.now)
    }

    func testAFutureTimeIsRefusedAndNothingIsSent() async {
        let sent = Sent<EntryCareWrite>()
        let m = model { _, care in sent.add(care); return Fixed.saved(Fixed.logged(), at: care.occurredAt) }
        m.occurredAt = Fixed.now.addingTimeInterval(60)
        XCTAssertEqual(m.problems, [HomeEditText.futureTime])
        XCTAssertFalse(m.canSave)
        let saved = await m.save()
        XCTAssertNil(saved)
        XCTAssertTrue(sent.all.isEmpty)
    }

    func testSaveKeepsValuesHeldForPausedFieldsAndRetiredOptions() async {
        let sent = Sent<EntryCareWrite>()
        let m = model { _, care in sent.add(care); return Fixed.saved(Fixed.logged(), at: care.occurredAt) }
        m.values.setNumberText("148", for: "sys")
        m.note = "  "
        _ = await m.save()
        XCTAssertEqual(sent.all.first?.values,
                       ["sys": .number(148), "pos": .list(["lie"]), "arm": .string("Left")])
        XCTAssertEqual(sent.all.first?.occurredAt, Fixed.at("2026-11-07T23:00:00Z"))
    }

    func testAMoveWithinTheSameDayInTheReceiversZoneIsNotAMove() async {
        // 8 PM Nov 7 in Chicago, though Nov 8 in UTC.
        let later = Fixed.at("2026-11-08T02:00:00Z")
        let m = model { _, care in Fixed.saved(Fixed.logged(), at: care.occurredAt) }
        m.occurredAt = later
        let saved = await m.save()
        XCTAssertEqual(saved?.detail.entry.at, later)
        XCTAssertNotNil(saved)
        XCTAssertNil(saved?.movedTo)
    }

    func testAMoveToAnotherDayInTheReceiversZoneSaysWhichDay() async {
        let m = model { _, care in Fixed.saved(Fixed.logged(), at: care.occurredAt) }
        m.occurredAt = Fixed.at("2026-11-06T15:00:00Z")
        let saved = await m.save()
        XCTAssertEqual(saved?.movedTo, Fixed.nov6)
    }

    func testA409IsSaidAndCannotBeRetried() async {
        let m = model { _, _ in throw EntryNotInState(message: nil) }
        let saved = await m.save()
        XCTAssertNil(saved)
        XCTAssertEqual(m.failure, .notInState)
        XCTAssertEqual(m.failureLine, HomeEditText.changedFirst)
        XCTAssertFalse(m.canSave)
    }

    func testDeletedElsewhereIsSaidAndCannotBeRetried() async {
        let m = model { _, _ in throw AppError.forStatus(404, serverMessage: nil) }
        _ = await m.save()
        XCTAssertEqual(m.failure, .gone)
        XCTAssertFalse(m.canSave)
        XCTAssertEqual(m.failure?.sendsHome, true, "as a delete would, Entry detail goes back to Home")
    }

    func testOnlyDeletedElsewhereSendsAnEditHome() {
        XCTAssertTrue(HomeEditFailure.gone.sendsHome)
        XCTAssertFalse(HomeEditFailure.notInState.sendsHome)
        XCTAssertFalse(HomeEditFailure.other(.transport).sendsHome)
    }

    func testTheEditsDefaultClockIsTheServers() {
        // Constructed without a clock: `latest` follows ServerClock.shared, not the phone.
        let m = EditEntryModel(Fixed.logged(), zone: Fixed.chicago, home: Fixed.home())
        let expected = ServerClock.shared.now()
        XCTAssertEqual(m.latest.timeIntervalSince(expected), 0, accuracy: 1)
    }

    func testAnyOtherFailureMayBeTriedAgain() async {
        let m = model { _, _ in throw URLError(.notConnectedToInternet) }
        _ = await m.save()
        guard case .other = m.failure else { return XCTFail("expected .other, got \(String(describing: m.failure))") }
        XCTAssertNotNil(m.failureLine)
        XCTAssertTrue(m.canSave)
    }
}

@MainActor
final class DeleteEntryModelTests: XCTestCase {
    private func model(_ detail: EntryDetailInfo,
                       delete: @escaping @Sendable (String) async throws -> EntryDetailInfo?) -> DeleteEntryModel {
        var home = Fixed.home()
        home.deleteEntry = delete
        return DeleteEntryModel(detail, home: home)
    }

    func testSaysWhatDeletingLeavesBehind() {
        XCTAssertEqual(model(Fixed.logged()) { _ in nil }.explanation, HomeEditText.adHocGone)
        XCTAssertEqual(model(Fixed.logged(planned: true, schedule: "Morning")) { _ in nil }.explanation,
                       "It came from the Morning schedule, so that time will be waiting to be logged again.")
        XCTAssertEqual(model(Fixed.logged(planned: true)) { _ in nil }.explanation,
                       "It was planned, so that time will be waiting to be logged again.")
    }

    func testAPlannedEntryWaitsAgain() async {
        let waiting = Fixed.skippedAhead
        let m = model(Fixed.logged(planned: true)) { _ in waiting }
        let outcome = await m.confirm()
        XCTAssertEqual(outcome, .waitingAgain(waiting))
    }

    func testAnAdHocEntryIsGone() async {
        let outcome = await model(Fixed.logged()) { _ in nil }.confirm()
        XCTAssertEqual(outcome, .gone)
    }

    func testDeletedElsewhereFirstIsGoneAllTheSame() async {
        let outcome = await model(Fixed.logged()) { _ in throw AppError.forStatus(404, serverMessage: nil) }.confirm()
        XCTAssertEqual(outcome, .gone)
    }

    func testA409IsSaidAndCannotBeRetried() async {
        let m = model(Fixed.logged()) { _ in throw EntryNotInState(message: nil) }
        let outcome = await m.confirm()
        XCTAssertNil(outcome)
        XCTAssertEqual(m.failure, .notInState)
        XCTAssertEqual(m.failureLine, HomeEditText.changedFirst)
        XCTAssertFalse(m.canDelete)
    }
}

@MainActor
final class JournalNoteEditModelTests: XCTestCase {
    private func model(change: @escaping @Sendable (String, NoteWrite) async throws -> JournalNoteInfo
                           = { _, _ in throw URLError(.badURL) }) -> EditJournalNoteModel {
        var home = Fixed.home()
        home.changeJournalNote = change
        return EditJournalNoteModel(Fixed.note, zone: Fixed.chicago, home: home, clock: { Fixed.now })
    }

    func testAFutureTimeOrABlankNoteIsRefused() {
        let m = model()
        XCTAssertEqual(m.problems, [])
        m.at = Fixed.now.addingTimeInterval(1)
        m.body = "  "
        XCTAssertEqual(m.problems, [HomeEditText.noteRequired, HomeEditText.futureTime])
        XCTAssertFalse(m.canSave)
    }

    func testSaveSendsTheNoteTrimmed() async {
        let sent = Sent<NoteWrite>()
        let m = model { _, note in
            sent.add(note)
            return JournalNoteInfo(id: "n1", receiverID: "eleanor", at: note.at, body: note.body, authorName: "Dana",
                                   createdAt: Fixed.note.createdAt, updatedByName: "Trevor", updatedAt: Fixed.now)
        }
        m.body = " Better by lunch. \n"
        let saved = await m.save()
        XCTAssertEqual(saved?.body, "Better by lunch.")
        XCTAssertEqual(sent.all, [NoteWrite(at: Fixed.note.at, body: "Better by lunch.")])
    }

    func testDeletedElsewhereCannotBeSaved() async {
        let m = model { _, _ in throw AppError.forStatus(404, serverMessage: nil) }
        _ = await m.save()
        XCTAssertEqual(m.failureLine, HomeEditText.noteGoneSince)
        XCTAssertFalse(m.canSave)
        XCTAssertEqual(m.failure?.sendsHome, true, "as a delete would, Journal note goes back to Home")
    }

    func testDeletingIsDoneOnceGoneHereOrElsewhere() async {
        var home = Fixed.home()
        home.deleteJournalNote = { _ in }
        let deleted = await DeleteJournalNoteModel(Fixed.note, home: home).confirm()
        XCTAssertTrue(deleted)
        home.deleteJournalNote = { _ in throw AppError.forStatus(404, serverMessage: nil) }
        let goneAlready = await DeleteJournalNoteModel(Fixed.note, home: home).confirm()
        XCTAssertTrue(goneAlready)
        home.deleteJournalNote = { _ in throw URLError(.notConnectedToInternet) }
        let m = DeleteJournalNoteModel(Fixed.note, home: home)
        let failed = await m.confirm()
        XCTAssertFalse(failed)
        XCTAssertNotNil(m.failureLine)
    }
}

/// Home taking an edit's day with it (PRD "Entry detail": an edit that moves an entry to
/// another day takes the timeline with it).
@MainActor
final class HomeReflectsWritesTests: XCTestCase {
    private let days = Sent<LocalDay>()

    private func home() -> HomeModel {
        let days = days
        var service = Fixed.home()
        service.dayTimeline = { _, day in
            days.add(day)
            return DayTimeline(day: day, items: [])
        }
        var trackers = TrackersFixtures.service()
        trackers.listTrackers = { _ in [] }
        return HomeModel(home: service, trackers: trackers, clock: { Fixed.now })
    }

    func testAnEditThatMovedAnEntryTakesTheDayWithIt() async {
        let model = home()
        await model.show(Fixed.eleanor)
        XCTAssertEqual(model.day, Fixed.nov7)
        await model.reflect(HomeWrite(receiverID: "eleanor", movedTo: Fixed.nov6))
        XCTAssertEqual(model.day, Fixed.nov6)
        XCTAssertEqual(days.all.last, Fixed.nov6)
    }

    func testAWriteThatMovedNothingReadsHomeAgainOnTheSameDay() async {
        let model = home()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        await model.reflect(HomeWrite(receiverID: "eleanor"))
        XCTAssertEqual(model.day, Fixed.nov6)
        XCTAssertEqual(days.all, [Fixed.nov7, Fixed.nov6, Fixed.nov6])
    }

    func testADayAheadOfTodayIsNotShown() async {
        let model = home()
        await model.show(Fixed.eleanor)
        await model.reflect(HomeWrite(receiverID: "eleanor", movedTo: LocalDay(year: 2026, month: 11, day: 8)))
        XCTAssertEqual(model.day, Fixed.nov7)
    }

    func testAWriteAboutSomeoneElseReadsNothing() async {
        let model = home()
        await model.show(Fixed.eleanor)
        await model.reflect(HomeWrite(receiverID: "walter", movedTo: Fixed.nov6))
        XCTAssertEqual(model.day, Fixed.nov7)
        XCTAssertEqual(days.all, [Fixed.nov7])
    }

    func testAQuickLogRunForSomeoneElseIsOnlyAPlainRefresh() async {
        let model = home()
        await model.show(Fixed.eleanor)
        await model.stepBack()
        await model.reflect(QuickLogModel.Outcome(receiverID: "walter", planning: false, latestDay: Fixed.nov7,
                                                  savedAny: true))
        XCTAssertEqual(model.day, Fixed.nov6, "Walter's day says nothing about Eleanor's timeline")
        XCTAssertEqual(days.all, [Fixed.nov7, Fixed.nov6, Fixed.nov6])
    }

    func testTheLogCountsEachWrite() {
        var log = HomeWriteLog()
        log.record(HomeWrite(receiverID: "eleanor"))
        log.record(HomeWrite(receiverID: "eleanor", movedTo: Fixed.nov6))
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.last, HomeWrite(receiverID: "eleanor", movedTo: Fixed.nov6))
    }
}
