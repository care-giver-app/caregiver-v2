import XCTest
@testable import Caregiver

/// Fixed instants and zones: nothing here reads the device clock or zone.
private enum Q {
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Sat Nov 7 2026, 6:00 PM in Chicago.
    static let now = at("2026-11-08T00:00:00Z")
    static let today = LocalDay(year: 2026, month: 11, day: 7)

    static let admin = TeamReceiver(id: "r1", name: "Eleanor", timeZone: chicago, canManage: true)
    static let caregiver = TeamReceiver(id: "r1", name: "Eleanor", timeZone: chicago, canManage: false)

    static func tracker(_ id: String, _ name: String, _ status: TrackerStatus = .active) -> TrackerItem {
        TrackerItem(id: id, name: name, icon: "heart", color: "#1c8fe0", status: status,
                    lastLoggedAt: nil, pausedAt: nil, needsAttention: false)
    }

    static let bp = tracker("bp", "Blood pressure")
    static let medication = tracker("medication", "Medication")
    static let walk = tracker("walk", "Walk", .paused)
    static let trackers = [bp, medication, walk]

    static let bpBadge = TrackerBadgeInfo(id: "bp", name: "Blood pressure", icon: "heart", color: "#1c8fe0")
    static let medBadge = TrackerBadgeInfo(id: "medication", name: "Medication", icon: "heart", color: "#1c8fe0")

    static let bpFields = [
        TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", required: true,
                         range: ValueRangeInfo(low: 90, high: 140), options: []),
        TrackerFieldInfo(id: "dia", label: "Diastolic", kind: .number, unit: "mmHg", required: true, options: []),
        TrackerFieldInfo(id: "old", label: "Old", kind: .text, unit: nil, paused: true, options: []),
    ]

    static let medFields = [
        TrackerFieldInfo(id: "given", label: "Given", kind: .boolean, unit: nil, required: true, options: []),
        TrackerFieldInfo(id: "dose", label: "Dose", kind: .choice, unit: nil, options: [
            ChoiceOptionInfo(id: "lis10", label: "Lisinopril 10 mg", retired: false),
            ChoiceOptionInfo(id: "lis5", label: "Lisinopril 5 mg", retired: true),
        ]),
    ]

    static func profile(_ t: TrackerItem, _ fields: [TrackerFieldInfo]) -> TrackerProfile {
        TrackerProfile(id: t.id, name: t.name, icon: t.icon, color: t.color, status: t.status, pausedAt: nil,
                       fields: fields, gapHours: nil, scheduleCount: 1, lastLoggedAt: nil, attention: [])
    }

    /// Last night's dose, unrecorded, pre-filled with an option retired since.
    static let unrecordedDose = ReceiverEntryItem(tracker: medBadge, entry: TrackerEntry(
        id: "dose-last-night", state: .unrecorded, at: at("2026-11-07T02:00:00Z"),
        values: ["dose": .list(["lis10", "lis5"])], note: nil, byName: nil, scheduleName: "Evening"))
    /// Tonight's 7 PM check.
    static let tonightCheck = ReceiverEntryItem(tracker: bpBadge, entry: TrackerEntry(
        id: "check-tonight", state: .scheduled, at: at("2026-11-08T01:00:00Z"),
        values: [:], note: nil, byName: nil, scheduleName: "Evening check"))
    static let waiting = [unrecordedDose, tonightCheck]

    static func detail(_ id: String, _ state: EntryState, at: Date, tracker: TrackerBadgeInfo = medBadge)
        -> EntryDetailInfo {
        EntryDetailInfo(entry: TrackerEntry(id: id, state: state, at: at, values: [:], note: nil, byName: "Trevor"),
                        tracker: tracker, fields: tracker.id == "bp" ? bpFields : medFields, planned: true,
                        occurrenceAt: at, unrecordedAlert: false, settledAt: now, updatedByName: nil,
                        updatedAt: nil, outOfRange: [])
    }
}

/// Every write the run makes, in order.
private final class Writes: @unchecked Sendable {
    enum Call: Equatable {
        case add(trackerID: String, NewEntryWrite)
        case log(entryID: String, EntryCareWrite)
        case skip(entryID: String, note: String?)
        case note(receiverID: String, NoteWrite)
        case detail(trackerID: String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }
    var writes: [Call] { calls.filter { if case .detail = $0 { return false } else { return true } } }

    func record(_ c: Call) { lock.withLock { _calls.append(c) } }

    /// Item ids whose write should fail, and how.
    var failures: [String: any Error] = [:]
    var failLoad = false
    var failFields = false
    /// Awaited inside a journal note's write before it answers, to hold one in flight.
    var holdNote: (@Sendable () async -> Void)?
}

@MainActor
private final class Clock {
    var now = Q.now
}

@MainActor
final class QuickLogModelTests: XCTestCase {
    private var writes = Writes()
    private var clock = Clock()

    private func model(_ start: QuickLogStart = .pick, receiver: TeamReceiver = Q.admin,
                       waiting: [ReceiverEntryItem] = Q.waiting,
                       trackers: [TrackerItem] = Q.trackers) -> QuickLogModel {
        let w = writes
        var home = HomeFixtures.service()
        home.waiting = { _ in
            if w.failLoad { throw URLError(.notConnectedToInternet) }
            return waiting
        }
        home.addEntry = { id, write in
            w.record(.add(trackerID: id, write))
            if let e = w.failures[id] { throw e }
            let planned = write.at.map { $0 > Q.now } ?? false
            return Q.detail("new-\(id)", planned ? .scheduled : .logged, at: write.at ?? Q.now,
                            tracker: id == "bp" ? Q.bpBadge : Q.medBadge)
        }
        home.logEntry = { id, care in
            w.record(.log(entryID: id, care))
            if let e = w.failures[id] { throw e }
            return Q.detail(id, .logged, at: care.occurredAt)
        }
        home.skipEntry = { id, note in
            w.record(.skip(entryID: id, note: note))
            if let e = w.failures[id] { throw e }
            return Q.detail(id, .skipped, at: Q.unrecordedDose.entry.at)
        }
        home.addJournalNote = { id, note in
            w.record(.note(receiverID: id, note))
            if let hold = w.holdNote { await hold() }
            if let e = w.failures["note"] { throw e }
            return JournalNoteInfo(id: "n1", receiverID: id, at: note.at, body: note.body, authorName: "Trevor",
                                   createdAt: Q.now, updatedByName: nil, updatedAt: nil)
        }
        var service = TrackersFixtures.service()
        service.listTrackers = { _ in
            if w.failLoad { throw URLError(.notConnectedToInternet) }
            return trackers
        }
        service.trackerDetail = { id in
            w.record(.detail(trackerID: id))
            if w.failFields { throw URLError(.notConnectedToInternet) }
            switch id {
            case "bp": return Q.profile(Q.bp, Q.bpFields)
            case "medication": return Q.profile(Q.medication, Q.medFields)
            default: throw URLError(.badURL)
            }
        }
        let clock = clock
        return QuickLogModel(start: start, receiver: receiver, home: home, trackers: service,
                             clock: { clock.now })
    }

    private func loaded(_ start: QuickLogStart = .pick, receiver: TeamReceiver = Q.admin,
                        waiting: [ReceiverEntryItem] = Q.waiting,
                        trackers: [TrackerItem] = Q.trackers) async -> QuickLogModel {
        let m = model(start, receiver: receiver, waiting: waiting, trackers: trackers)
        await m.load()
        return m
    }

    /// Picks `items`, keeps now, and goes into the steps.
    private func intoSteps(_ m: QuickLogModel, _ items: [QuickLogModel.Item]) async {
        items.forEach(m.toggle)
        m.continueFromPick()
        await m.continueFromWhen()
    }

    private func bpReading(_ m: QuickLogModel, sys: String = "120", dia: String = "80") {
        m.updateDraft(.tracker(id: "bp")) {
            $0.values.setNumberText(sys, for: "sys")
            $0.values.setNumberText(dia, for: "dia")
        }
    }

    // MARK: Start modes

    func testPickStartsAtThePickerOnceLoaded() async {
        let m = model()
        XCTAssertEqual(m.part, .loading)
        await m.load()
        XCTAssertEqual(m.part, .pick)
        XCTAssertTrue(m.hasPickingPart)
        XCTAssertEqual(m.picked, [])
    }

    func testJournalNoteStartIsAtThePickerWithTheNotePicked() async {
        let m = await loaded(.journalNote)
        XCTAssertEqual(m.part, .pick)
        XCTAssertEqual(m.picked, [.journalNote])
        XCTAssertTrue(m.canContinueFromPick)
    }

    func testEntryStartHoldsThatEntryAtItsStepWithTheChoiceMade() async {
        let d = Q.detail("dose-last-night", .unrecorded, at: Q.unrecordedDose.entry.at)
        let m = model(.entry(d, choice: .skip))
        await m.load() // nothing to read
        XCTAssertEqual(m.part, .step(0))
        XCTAssertFalse(m.hasPickingPart)
        XCTAssertEqual(m.selection, [.occurrence(entryID: "dose-last-night")])
        XCTAssertEqual(m.draft(for: .occurrence(entryID: "dose-last-night")).choice, .skip)
        guard case .occurrence(let o, let fields) = m.steps.first else { return XCTFail("no step") }
        XCTAssertEqual(o.entry.id, "dose-last-night")
        XCTAssertEqual(fields.map(\.id), ["given", "dose"])
        XCTAssertFalse(m.offersFuture)
        XCTAssertTrue(writes.calls.isEmpty, "Entry detail's fields are used, not read again")
    }

    func testEntryStartStepsBackToWhenAndNoFurther() async {
        let d = Q.detail("dose-last-night", .unrecorded, at: Q.unrecordedDose.entry.at)
        let m = model(.entry(d, choice: .logIt))
        m.back()
        XCTAssertEqual(m.part, .when)
        XCTAssertFalse(m.canGoBack)
        m.back()
        XCTAssertEqual(m.part, .when)
        m.when = .future
        XCTAssertEqual(m.whenProblems.first, QuickLogText.futureProblem)
        m.when = .now
        await m.continueFromWhen()
        XCTAssertEqual(m.part, .step(0))
    }

    func testTrackerStartWithNothingWaitingSkipsPicking() async {
        let m = await loaded(.tracker(id: "medication"), waiting: [Q.tonightCheck])
        XCTAssertEqual(m.part, .when)
        XCTAssertEqual(m.picked, [.tracker(id: "medication")])
        XCTAssertFalse(m.canGoBack)
    }

    func testTrackerStartWithOccurrencesWaitingPicksBetweenThemAndTheTracker() async {
        let m = await loaded(.tracker(id: "medication"))
        XCTAssertEqual(m.part, .pick)
        XCTAssertEqual(m.pickerOccurrences.map(\.entry.id), ["dose-last-night"])
        XCTAssertEqual(m.pickerTrackers.map(\.id), ["medication"])
        XCTAssertFalse(m.offersJournalNote)
        XCTAssertFalse(m.offersAddTracker)
        XCTAssertEqual(m.picked, [], "nothing is chosen for them")
    }

    func testLoadFailureCanBeRetried() async {
        writes.failLoad = true
        let m = await loaded()
        guard case .loadFailed = m.part else { return XCTFail("expected a failure, got \(m.part)") }
        writes.failLoad = false
        await m.load()
        XCTAssertEqual(m.part, .pick)
    }

    // MARK: The picker

    func testPickerLeadsWithWaitingThenActiveTrackersThenTheNote() async {
        let m = await loaded()
        XCTAssertEqual(m.pickerOccurrences.map(\.entry.id), ["dose-last-night", "check-tonight"],
                       "unrecorded first, in the API's order")
        XCTAssertEqual(m.pickerTrackers.map(\.id), ["bp", "medication"], "paused trackers are left out")
        XCTAssertTrue(m.offersJournalNote)
        XCTAssertTrue(m.offersAddTracker)
        XCTAssertNil(m.noTrackersLine)
    }

    func testOnlyAdminsAreOfferedANewTracker() async {
        let caregiver = await loaded(receiver: Q.caregiver)
        XCTAssertFalse(caregiver.offersAddTracker)
        caregiver.chooseAddTracker()
        XCTAssertFalse(caregiver.wantsAddTracker)

        let admin = await loaded()
        admin.chooseAddTracker()
        XCTAssertTrue(admin.wantsAddTracker)
    }

    func testNoActiveTrackersLeavesTheNoteAndTheAdminOffer() async {
        let admin = await loaded(waiting: [], trackers: [Q.walk])
        XCTAssertEqual(admin.pickerTrackers, [])
        XCTAssertTrue(admin.offersJournalNote)
        XCTAssertTrue(admin.offersAddTracker)
        XCTAssertNil(admin.noTrackersLine)

        let caregiver = await loaded(receiver: Q.caregiver, waiting: [], trackers: [Q.walk])
        XCTAssertTrue(caregiver.offersJournalNote)
        XCTAssertFalse(caregiver.offersAddTracker)
        XCTAssertEqual(caregiver.noTrackersLine, HomeText.noTrackersCaregiverLine)
    }

    func testSeveralAtOnceAndStepsFollowPickOrder() async {
        let m = await loaded()
        await intoSteps(m, [.journalNote, .tracker(id: "bp"), .occurrence(entryID: "dose-last-night")])
        XCTAssertEqual(m.part, .step(0))
        XCTAssertEqual(m.steps.count, 3)
        guard case .journalNote = m.steps[0], case .tracker(let t, let f) = m.steps[1],
              case .occurrence(let o, _) = m.steps[2] else { return XCTFail("steps out of order: \(m.steps)") }
        XCTAssertEqual(t.id, "bp")
        XCTAssertEqual(f.map(\.id), ["sys", "dia"], "paused fields have no place in a step")
        XCTAssertEqual(o.entry.id, "dose-last-night")
    }

    func testNothingPickedCannotGoOn() async {
        let m = await loaded()
        XCTAssertFalse(m.canContinueFromPick)
        m.continueFromPick()
        XCTAssertEqual(m.part, .pick)
    }

    // MARK: When

    func testAFutureTimePrunesNotesAndWaitingCareAndBringsThemBack() async {
        let m = await loaded()
        [.journalNote, .occurrence(entryID: "check-tonight"), .tracker(id: "bp")].forEach(m.toggle)
        m.continueFromPick()
        m.when = .future
        XCTAssertTrue(m.isPlanning)
        XCTAssertEqual(m.selection, [.tracker(id: "bp")])
        XCTAssertEqual(m.pickerOccurrences, [])
        XCTAssertFalse(m.offersJournalNote)
        XCTAssertEqual(m.pickerTrackers.map(\.id), ["bp", "medication"])
        m.when = .now
        XCTAssertEqual(m.selection, [.journalNote, .occurrence(entryID: "check-tonight"), .tracker(id: "bp")])
    }

    func testAFutureTimeWithNothingPlannableSaysSo() async {
        let m = await loaded(.journalNote)
        m.continueFromPick()
        m.when = .future
        XCTAssertEqual(m.whenProblems, [QuickLogText.nothingToPlan])
        await m.continueFromWhen()
        XCTAssertEqual(m.part, .when)
    }

    func testEarlierTodayMustBeTodayAndNotAfterNow() async {
        let m = await loaded()
        m.toggle(.tracker(id: "bp"))
        m.continueFromPick()
        m.when = .earlierToday
        XCTAssertEqual(m.earlierTime, Q.now.addingTimeInterval(-3600), "an hour ago by default")
        XCTAssertEqual(m.whenProblems, [])
        m.earlierTime = Q.now.addingTimeInterval(600)
        XCTAssertEqual(m.whenProblems, [QuickLogText.earlierTodayProblem])
        // 11:30 PM Friday in Chicago.
        m.earlierTime = Q.at("2026-11-07T05:30:00Z")
        XCTAssertEqual(m.whenProblems, [QuickLogText.earlierTodayProblem])
        // 12:30 AM Saturday.
        m.earlierTime = Q.at("2026-11-07T06:30:00Z")
        XCTAssertEqual(m.whenProblems, [])
    }

    func testAFutureTimeMustBeMoreThanAMinuteAhead() async {
        let m = await loaded()
        m.toggle(.tracker(id: "bp"))
        m.continueFromPick()
        m.when = .future
        XCTAssertEqual(m.futureTime, Q.at("2026-11-08T01:00:00Z"), "the first whole hour an hour ahead")
        XCTAssertEqual(m.whenProblems, [])
        m.futureTime = Q.now.addingTimeInterval(30)
        XCTAssertEqual(m.whenProblems, [QuickLogText.futureProblem])
    }

    func testFieldsThatCannotBeReadKeepTheRunAtWhen() async {
        writes.failFields = true
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        XCTAssertEqual(m.part, .when)
        XCTAssertNotNil(m.fieldsFailed)
        writes.failFields = false
        await m.continueFromWhen()
        XCTAssertEqual(m.part, .step(0))
        XCTAssertNil(m.fieldsFailed)
    }

    func testFieldsAreReadOncePerTracker() async {
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "medication"), .occurrence(entryID: "dose-last-night")])
        m.back()
        await m.continueFromWhen()
        XCTAssertEqual(writes.calls, [.detail(trackerID: "medication")])
    }

    // MARK: Steps

    func testLoggingRequiresEveryRequiredFieldButPlanningNothing() async {
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        XCTAssertEqual(m.problems(for: .tracker(id: "bp")), ["Systolic is required.", "Diastolic is required."])
        await m.advance()
        XCTAssertEqual(m.part, .step(0))
        m.back()
        m.when = .future
        await m.continueFromWhen()
        XCTAssertEqual(m.problems(for: .tracker(id: "bp")), [])
    }

    func testANumberThatIsNotOneIsRefusedButOneOutOfRangeIsNot() async {
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        bpReading(m, sys: "12o")
        XCTAssertEqual(m.problems(for: .tracker(id: "bp")), ["Systolic: enter a number."])
        bpReading(m, sys: "190")
        XCTAssertEqual(m.problems(for: .tracker(id: "bp")), [])
    }

    func testAnOccurrencePreFillsFromItsPlanAndASkipNeedsNothing() async {
        let m = await loaded()
        await intoSteps(m, [.occurrence(entryID: "dose-last-night")])
        let item = QuickLogModel.Item.occurrence(entryID: "dose-last-night")
        XCTAssertEqual(m.draft(for: item).values.chosen(for: "dose"), ["lis10", "lis5"])
        XCTAssertEqual(m.draft(for: item).choice, .logIt)
        XCTAssertEqual(m.problems(for: item), ["Given is required."])
        m.updateDraft(item) { $0.choice = .skip }
        XCTAssertEqual(m.problems(for: item), [])
    }

    func testAJournalNoteNeedsABody() async {
        let m = await loaded(.journalNote)
        m.continueFromPick()
        await m.continueFromWhen()
        XCTAssertEqual(m.problems(for: .journalNote), [QuickLogText.noteRequired])
        m.updateDraft(.journalNote) { $0.note = "   " }
        XCTAssertEqual(m.problems(for: .journalNote), [QuickLogText.noteRequired])
        m.updateDraft(.journalNote) { $0.note = String(repeating: "a", count: 5001) }
        XCTAssertEqual(m.problems(for: .journalNote), [QuickLogText.noteTooLong(5000)])
    }

    func testStepsWalkForwardAndBackKeepingWhatWasEntered() async {
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp"), .journalNote])
        bpReading(m)
        await m.advance()
        XCTAssertEqual(m.part, .step(1))
        XCTAssertTrue(m.isLastStep)
        m.updateDraft(.journalNote) { $0.note = "Calm evening." }
        m.back()
        XCTAssertEqual(m.part, .step(0))
        m.back()
        XCTAssertEqual(m.part, .when)
        m.back()
        XCTAssertEqual(m.part, .pick)
        m.continueFromPick()
        await m.continueFromWhen()
        XCTAssertEqual(m.draft(for: .tracker(id: "bp")).values.numberText(for: "sys"), "120")
        XCTAssertEqual(m.draft(for: .journalNote).note, "Calm evening.")
    }

    func testDroppingAnItemDropsWhatWasEnteredForIt() async {
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        bpReading(m)
        m.back()
        m.back()
        m.toggle(.tracker(id: "bp"))
        XCTAssertEqual(m.picked, [])
        m.toggle(.tracker(id: "bp"))
        XCTAssertEqual(m.draft(for: .tracker(id: "bp")), QuickLogModel.Draft())
    }

    // MARK: Saving

    func testALoggingRunSendsOneRequestPerItemAtTheRunsOneTime() async {
        let m = await loaded()
        await intoSteps(m, [.occurrence(entryID: "dose-last-night"), .occurrence(entryID: "check-tonight"),
                            .tracker(id: "bp"), .journalNote])
        m.updateDraft(.occurrence(entryID: "dose-last-night")) {
            $0.values.setBool(true, for: "given")
            $0.note = "With dinner."
        }
        await m.advance()
        m.updateDraft(.occurrence(entryID: "check-tonight")) {
            $0.choice = .skip
            $0.note = "Asleep."
        }
        await m.advance()
        bpReading(m, sys: " 152 ")
        await m.advance()
        m.updateDraft(.journalNote) { $0.note = "  Quiet day.  " }
        clock.now = Q.now.addingTimeInterval(120)
        await m.advance()

        XCTAssertEqual(m.part, .result)
        let at = Q.now.addingTimeInterval(120)
        XCTAssertEqual(writes.writes, [
            .log(entryID: "dose-last-night", EntryCareWrite(
                occurredAt: at, values: ["given": .bool(true), "dose": .list(["lis10"])], note: "With dinner.")),
            .skip(entryID: "check-tonight", note: "Asleep."),
            .add(trackerID: "bp", NewEntryWrite(at: nil, values: ["sys": .number(152), "dia": .number(80)],
                                                note: "", unrecordedAlert: false)),
            .note(receiverID: "r1", NoteWrite(at: at, body: "Quiet day.")),
        ])
        XCTAssertEqual(m.results.map(\.saved), [true, true, true, true])
        XCTAssertEqual(m.results.map(\.title), ["Medication", "Blood pressure", "Blood pressure",
                                                QuickLogText.journalNote])
        XCTAssertEqual(m.outcome, QuickLogModel.Outcome(receiverID: "r1", planning: false, latestDay: Q.today, savedAny: true))
    }

    func testAnEarlierTimeIsSentForEveryItem() async {
        let m = await loaded()
        [.tracker(id: "bp"), .journalNote].forEach(m.toggle)
        m.continueFromPick()
        m.when = .earlierToday
        let earlier = Q.at("2026-11-07T20:15:00Z") // 2:15 PM
        m.earlierTime = earlier
        await m.continueFromWhen()
        bpReading(m)
        await m.advance()
        m.updateDraft(.journalNote) { $0.note = "Lunch out." }
        await m.advance()
        XCTAssertEqual(writes.writes, [
            .add(trackerID: "bp", NewEntryWrite(at: earlier, values: ["sys": .number(120), "dia": .number(80)],
                                                note: "", unrecordedAlert: false)),
            .note(receiverID: "r1", NoteWrite(at: earlier, body: "Lunch out.")),
        ])
    }

    func testAPlanningRunPreFillsAndAsksWhetherToAlert() async {
        let m = await loaded()
        [.journalNote, .tracker(id: "medication"), .tracker(id: "bp")].forEach(m.toggle)
        m.continueFromPick()
        m.when = .future
        let tuesday = Q.at("2026-11-10T15:00:00Z")
        m.futureTime = tuesday
        m.alertIfUnrecorded = true
        await m.continueFromWhen()
        XCTAssertEqual(m.steps.count, 2, "the note left the run")
        m.updateDraft(.tracker(id: "medication")) {
            $0.values.choose("lis10", in: Q.medFields[1])
        }
        await m.advance()
        await m.advance() // a reading nobody has taken yet is left blank
        XCTAssertEqual(m.part, .result)
        XCTAssertEqual(writes.writes, [
            .add(trackerID: "medication", NewEntryWrite(at: tuesday, values: ["dose": .list(["lis10"])],
                                                        note: "", unrecordedAlert: true)),
            .add(trackerID: "bp", NewEntryWrite(at: tuesday, values: [:], note: "", unrecordedAlert: true)),
        ])
        XCTAssertEqual(m.outcome, QuickLogModel.Outcome(receiverID: "r1", planning: true, latestDay: LocalDay(year: 2026, month: 11, day: 10),
                                                        savedAny: true))
    }

    func testAFutureTimeThatHasComeSendsTheRunBackToWhen() async {
        let m = await loaded()
        m.toggle(.tracker(id: "bp"))
        m.continueFromPick()
        m.when = .future
        await m.continueFromWhen()
        clock.now = m.futureTime
        await m.advance()
        XCTAssertEqual(m.part, .when)
        XCTAssertEqual(m.whenProblems, [QuickLogText.futureProblem])
        XCTAssertEqual(writes.writes, [])
    }

    func testEveryItemIsAttemptedAndTheResultSaysWhichFailed() async {
        writes.failures = [
            "dose-last-night": EntryNotInState(message: "the entry is not in a state this allows; reload it"),
            "bp": AppError.forStatus(400, serverMessage: "invalid entry: \"Systolic\" is required"),
        ]
        let m = await loaded()
        await intoSteps(m, [.occurrence(entryID: "dose-last-night"), .tracker(id: "bp"), .journalNote])
        m.updateDraft(.occurrence(entryID: "dose-last-night")) { $0.values.setBool(true, for: "given") }
        await m.advance()
        bpReading(m)
        await m.advance()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()

        XCTAssertEqual(writes.writes.count, 3)
        XCTAssertEqual(m.results.map(\.status), [
            .failed(QuickLogText.notInState),
            .failed("invalid entry: \"Systolic\" is required"),
            m.results[2].status,
        ])
        XCTAssertTrue(m.results[2].saved)
        XCTAssertEqual(m.outcome?.savedAny, true)
    }

    func testA409OnAPausedTrackerSaysSo() async {
        writes.failures = ["bp": EntryNotInState(message: "the tracker is paused")]
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        bpReading(m)
        await m.advance()
        XCTAssertEqual(m.results.map(\.status), [.failed(QuickLogText.trackerPaused)])
        XCTAssertEqual(m.outcome, QuickLogModel.Outcome(receiverID: "r1", planning: false, latestDay: nil, savedAny: false))
    }

    func testATransportFailureIsAFailureLine() async {
        writes.failures = ["note": URLError(.notConnectedToInternet)]
        let m = await loaded(.journalNote)
        m.continueFromPick()
        await m.continueFromWhen()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()
        XCTAssertEqual(m.results.map(\.status), [.failed(AppError.transport.message)])
    }

    func testEntryDetailsSkipIsSentWithItsNote() async {
        let d = Q.detail("dose-last-night", .unrecorded, at: Q.unrecordedDose.entry.at)
        let m = model(.entry(d, choice: .skip))
        m.updateDraft(.occurrence(entryID: "dose-last-night")) { $0.note = "Held: low blood pressure." }
        XCTAssertTrue(m.isLastStep)
        await m.advance()
        XCTAssertEqual(writes.writes, [.skip(entryID: "dose-last-night", note: "Held: low blood pressure.")])
        XCTAssertEqual(m.outcome?.savedAny, true)
        XCTAssertEqual(m.outcome?.planning, false)
    }

    func testOutcomeIsNilUntilTheResult() async {
        let m = await loaded()
        XCTAssertNil(m.outcome)
    }

    // MARK: Retry (Figma 448:4570)

    func testAFailedLineCanBeRetriedAndTheOutcomeFollows() async {
        writes.failures = ["note": URLError(.notConnectedToInternet)]
        let m = await loaded(.journalNote)
        m.continueFromPick()
        await m.continueFromWhen()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()
        XCTAssertTrue(m.results[0].retryable)
        XCTAssertEqual(m.outcome?.savedAny, false)

        writes.failures = [:]
        await m.retry(.journalNote)
        XCTAssertTrue(m.results[0].saved)
        XCTAssertEqual(m.outcome?.savedAny, true)
        XCTAssertEqual(writes.writes.count, 2)
        XCTAssertEqual(m.retrying, [])
    }

    func testARefusalForTheEntrysStateIsNotRetried() async {
        writes.failures = ["bp": EntryNotInState(message: "the tracker is paused")]
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        bpReading(m)
        await m.advance()
        XCTAssertFalse(m.results[0].retryable)
        await m.retry(.tracker(id: "bp"))
        XCTAssertEqual(writes.writes.count, 1)
    }

    func testRetryingAPlanWhoseTimeHasComeSaysSoAndSendsNothing() async {
        writes.failures = ["bp": AppError.forStatus(503, serverMessage: nil)]
        let m = await loaded()
        m.toggle(.tracker(id: "bp"))
        m.continueFromPick()
        m.when = .future
        await m.continueFromWhen()
        await m.advance()
        XCTAssertEqual(m.outcome?.planning, true)
        XCTAssertTrue(m.results[0].retryable)

        writes.failures = [:]
        clock.now = m.futureTime
        await m.retry(.tracker(id: "bp"))
        XCTAssertEqual(m.results[0].status, .failed(QuickLogText.futureProblem))
        XCTAssertFalse(m.results[0].retryable)
        XCTAssertEqual(writes.writes.count, 1)
    }

    // MARK: Review fixes

    func testAnEarlierTimeThatIsNoLongerTodaySendsTheRunBackToWhen() async {
        let m = await loaded()
        m.toggle(.tracker(id: "bp"))
        m.continueFromPick()
        m.when = .earlierToday
        m.earlierTime = Q.at("2026-11-07T20:15:00Z") // 2:15 PM Saturday
        await m.continueFromWhen()
        bpReading(m)
        clock.now = Q.at("2026-11-08T06:30:00Z") // 12:30 AM Sunday in Chicago
        await m.advance()
        XCTAssertEqual(m.part, .when)
        XCTAssertEqual(m.whenProblems, [QuickLogText.earlierTodayProblem])
        XCTAssertEqual(writes.writes, [])
    }

    func testATrackerPausedSinceTrackerDetailSaysSoAndOffersOnlyCancel() async {
        let m = await loaded(.tracker(id: "walk"))
        XCTAssertEqual(m.part, .nothingToLog(QuickLogText.scopedTrackerPaused))
        XCTAssertFalse(m.canGoBack)
        XCTAssertFalse(m.hasPickingPart)
        XCTAssertNil(m.outcome)

        let gone = await loaded(.tracker(id: "deleted"))
        XCTAssertEqual(gone.part, .nothingToLog(QuickLogText.scopedTrackerGone))
    }

    func testANewEntryWhoseAnswerWasLostIsNotRetriedButHomeRefreshes() async {
        writes.failures = ["bp": URLError(.timedOut)]
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp")])
        bpReading(m)
        await m.advance()
        XCTAssertEqual(m.results.map(\.status), [.failed(QuickLogText.outcomeUnknown)])
        XCTAssertFalse(m.results[0].retryable)
        XCTAssertTrue(m.results[0].mightHaveSaved)
        XCTAssertEqual(m.outcome?.savedAny, true, "it may have saved, so the screens beneath read again")
        await m.retry(.tracker(id: "bp"))
        XCTAssertEqual(writes.writes.count, 1)
    }

    func testAJournalNoteWhoseAnswerWasLostIsNotRetried() async {
        writes.failures = ["note": URLError(.networkConnectionLost)]
        let m = await loaded(.journalNote)
        m.continueFromPick()
        await m.continueFromWhen()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()
        XCTAssertEqual(m.results.map(\.status), [.failed(QuickLogText.outcomeUnknown)])
        XCTAssertFalse(m.results[0].retryable)
    }

    func testANewEntryRefusedByTheServerOrNeverSentCanBeRetried() async {
        writes.failures = ["bp": AppError.forStatus(502, serverMessage: nil),
                           "medication": URLError(.notConnectedToInternet)]
        let m = await loaded()
        await intoSteps(m, [.tracker(id: "bp"), .tracker(id: "medication")])
        bpReading(m)
        await m.advance()
        m.updateDraft(.tracker(id: "medication")) { $0.values.setBool(true, for: "given") }
        await m.advance()
        XCTAssertEqual(m.results.map(\.retryable), [true, true])
        XCTAssertEqual(m.results.map(\.mightHaveSaved), [false, false])
        XCTAssertEqual(m.outcome?.savedAny, false)
    }

    func testALogWhoseAnswerWasLostIsRetriedAndA409ThenMayBeItsOwnFirstAttempt() async {
        writes.failures = ["dose-last-night": URLError(.timedOut)]
        let m = await loaded()
        await intoSteps(m, [.occurrence(entryID: "dose-last-night")])
        m.updateDraft(.occurrence(entryID: "dose-last-night")) { $0.values.setBool(true, for: "given") }
        await m.advance()
        XCTAssertTrue(m.results[0].retryable, "a second log of the same entry is refused, not doubled")
        XCTAssertEqual(m.outcome?.savedAny, false)

        writes.failures = ["dose-last-night": EntryNotInState(message: "the entry is not in a state this allows")]
        await m.retry(.occurrence(entryID: "dose-last-night"))
        XCTAssertEqual(m.results[0].status, .failed(QuickLogText.notInState))
        XCTAssertFalse(m.results[0].retryable)
        XCTAssertTrue(m.results[0].mightHaveSaved)
        XCTAssertEqual(m.outcome?.savedAny, true)
    }

    func testAFirst409IsNotTakenForASave() async {
        writes.failures = ["dose-last-night": EntryNotInState(message: nil)]
        let m = await loaded()
        await intoSteps(m, [.occurrence(entryID: "dose-last-night")])
        m.updateDraft(.occurrence(entryID: "dose-last-night")) { $0.values.setBool(true, for: "given") }
        await m.advance()
        XCTAssertFalse(m.results[0].mightHaveSaved)
        XCTAssertEqual(m.outcome?.savedAny, false)
    }

    func testWhatMayHaveLanded() {
        XCTAssertTrue(QuickLogModel.mayHaveLanded(URLError(.timedOut)))
        XCTAssertTrue(QuickLogModel.mayHaveLanded(URLError(.networkConnectionLost)))
        XCTAssertFalse(QuickLogModel.mayHaveLanded(URLError(.notConnectedToInternet)))
        XCTAssertFalse(QuickLogModel.mayHaveLanded(URLError(.cannotConnectToHost)))
        XCTAssertFalse(QuickLogModel.mayHaveLanded(AppError.forStatus(500, serverMessage: nil)))
        XCTAssertFalse(QuickLogModel.mayHaveLanded(EntryNotInState(message: nil)))
    }

    func testTheOutcomeNamesWhoseRunItWas() async {
        let m = await loaded(.journalNote)
        m.continueFromPick()
        await m.continueFromWhen()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()
        XCTAssertEqual(m.outcome?.receiverID, "r1")
    }

    func testTheRunIsSavingUntilARetryInFlightIsAnswered() async {
        writes.failures = ["note": AppError.forStatus(503, serverMessage: nil)]
        let m = await loaded(.journalNote)
        m.continueFromPick()
        await m.continueFromWhen()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()
        XCTAssertFalse(m.isSaving)

        writes.failures = [:]
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        writes.holdNote = {
            started.continuation.yield()
            for await _ in release.stream { break }
        }
        let retry = Task { await m.retry(.journalNote) }
        for await _ in started.stream { break }
        XCTAssertTrue(m.isSaving, "Done waits for it")
        XCTAssertEqual(m.outcome?.savedAny, false)
        release.continuation.yield()
        await retry.value
        XCTAssertFalse(m.isSaving)
        XCTAssertEqual(m.outcome?.savedAny, true)
    }

    func testNowIsTheInjectedClocksForALogAndANote() async {
        clock.now = Q.now.addingTimeInterval(-300) // the server's clock, five minutes behind the phone
        let m = await loaded()
        await intoSteps(m, [.occurrence(entryID: "dose-last-night"), .journalNote])
        m.updateDraft(.occurrence(entryID: "dose-last-night")) { $0.values.setBool(true, for: "given") }
        await m.advance()
        m.updateDraft(.journalNote) { $0.note = "Fine." }
        await m.advance()
        let at = Q.now.addingTimeInterval(-300)
        XCTAssertEqual(writes.writes.compactMap { call -> Date? in
            switch call {
            case .log(_, let care): care.occurredAt
            case .note(_, let note): note.at
            default: nil
            }
        }, [at, at])
    }

    // MARK: What the sheet says

    func testStepLabelsAndResultHeadings() {
        XCTAssertEqual(QuickLogText.stepLabel(1, of: 3, planning: false), "STEP 2 OF 3")
        XCTAssertEqual(QuickLogText.stepLabel(0, of: 2, planning: true), "STEP 1 OF 2 · PLANNING")
        XCTAssertEqual(QuickLogText.resultsHeading(saved: 3, of: 3, planning: false), "3 saved")
        XCTAssertEqual(QuickLogText.resultsHeading(saved: 2, of: 3, planning: false), "2 of 3 saved")
        XCTAssertEqual(QuickLogText.resultsHeading(saved: 2, of: 2, planning: true), "2 planned")
        XCTAssertEqual(QuickLogText.resultsHeading(saved: 0, of: 1, planning: true), "0 of 1 planned")
    }

    func testAnOccurrenceSaysItsDayWhenItIsNotToday() {
        // Tonight's 7 PM check, and last night's 8 PM dose, with "now" 6 PM Saturday.
        XCTAssertEqual(QuickLogText.occurrenceLine(Q.tonightCheck.entry, now: Q.now, zone: Q.chicago),
                       "Evening check · 7:00 PM")
        XCTAssertEqual(QuickLogText.occurrenceLine(Q.unrecordedDose.entry, now: Q.now, zone: Q.chicago),
                       "Evening · Yesterday at 8:00 PM")
    }

    func testEachResultLineSaysWhatBecameOfIt() {
        let skipped = Q.detail("dose-last-night", .skipped, at: Q.unrecordedDose.entry.at)
        let scheduledSkip = EntryDetailInfo(
            entry: TrackerEntry(id: "dose-last-night", state: .skipped, at: skipped.entry.at, values: [:],
                                note: nil, byName: "Trevor", scheduleName: "Evening"),
            tracker: Q.medBadge, fields: Q.medFields, planned: true, occurrenceAt: skipped.entry.at,
            unrecordedAlert: false, settledAt: Q.now, updatedByName: nil, updatedAt: nil, outOfRange: [])
        func line(_ item: QuickLogModel.Item, _ status: QuickLogModel.Result.Status, planning: Bool = false) -> String {
            QuickLogText.resultLine(QuickLogModel.Result(item: item, title: "", tracker: nil, status: status),
                                    planning: planning, now: Q.now, zone: Q.chicago)
        }
        XCTAssertEqual(line(.occurrence(entryID: "dose-last-night"), .savedEntry(scheduledSkip)), "Evening · skipped")
        XCTAssertEqual(line(.tracker(id: "bp"), .savedEntry(Q.detail("n", .logged, at: Q.now, tracker: Q.bpBadge))),
                       "Logged")
        let tomorrow8 = Q.at("2026-11-08T14:00:00Z")
        XCTAssertEqual(line(.tracker(id: "bp"), .savedEntry(Q.detail("p", .scheduled, at: tomorrow8)), planning: true),
                       "Tomorrow at 8:00 AM")
        XCTAssertEqual(line(.journalNote, .failed("offline")), QuickLogText.couldNotSave)
    }
}

final class EntryValuesDraftTests: XCTestCase {
    private let choice = TrackerFieldInfo(id: "c", label: "Pick", kind: .choice, unit: nil, options: [
        ChoiceOptionInfo(id: "a", label: "A", retired: false),
        ChoiceOptionInfo(id: "b", label: "B", retired: false),
        ChoiceOptionInfo(id: "x", label: "X", retired: true),
    ])

    func testOneAnswerReplacesAndSeveralToggle() {
        var d = EntryValuesDraft()
        d.choose("a", in: choice)
        d.choose("b", in: choice)
        XCTAssertEqual(d.chosen(for: "c"), ["b"])
        d.choose("b", in: choice)
        XCTAssertEqual(d.chosen(for: "c"), [])

        let multiple = TrackerFieldInfo(id: "c", label: "Pick", kind: .choice, unit: nil, multiple: true,
                                        options: choice.options)
        d.choose("a", in: multiple)
        d.choose("b", in: multiple)
        XCTAssertEqual(d.chosen(for: "c"), ["a", "b"])
    }

    func testSentKeepsActiveFieldsAndOptionsAndTrimsText() {
        let fields = [
            choice,
            TrackerFieldInfo(id: "t", label: "Text", kind: .text, unit: nil, options: []),
            TrackerFieldInfo(id: "blank", label: "Blank", kind: .text, unit: nil, options: []),
            TrackerFieldInfo(id: "p", label: "Paused", kind: .boolean, unit: nil, paused: true, options: []),
        ]
        let d = EntryValuesDraft(["c": .list(["x", "a", "a"]), "t": .string("  hi "), "blank": .string("  "),
                                  "p": .bool(true), "gone": .number(1)])
        XCTAssertEqual(d.sent(for: fields), ["c": .list(["a"]), "t": .string("hi")])
    }

    func testNumbersAreParsedAndRefusedWhenNotNumbers() {
        let n = TrackerFieldInfo(id: "n", label: "N", kind: .number, unit: nil, required: true, options: [])
        var d = EntryValuesDraft(["n": .number(98.6)], locale: Locale(identifier: "en_US"))
        XCTAssertEqual(d.numberText(for: "n"), "98.6")
        d.setNumberText("inf", for: "n")
        XCTAssertEqual(d.problems(for: [n], requireAll: false), ["N: enter a number."])
        d.setNumberText("", for: "n")
        XCTAssertEqual(d.problems(for: [n], requireAll: false), [])
        XCTAssertEqual(d.problems(for: [n], requireAll: true), ["N is required."])
        d.setNumberText("1e3", for: "n")
        XCTAssertEqual(d.sent(for: [n]), ["n": .number(1000)])
    }

    func testABlankRequiredTextOrEmptyChoiceIsUnanswered() {
        let t = TrackerFieldInfo(id: "t", label: "Text", kind: .text, unit: nil, required: true, options: [])
        let c = TrackerFieldInfo(id: "c", label: "Pick", kind: .choice, unit: nil, required: true,
                                 options: choice.options)
        let d = EntryValuesDraft(["t": .string("   "), "c": .list(["x"])])
        XCTAssertEqual(d.problems(for: [t, c], requireAll: true), ["Text is required.", "Pick is required."])
    }

    func testBooleansToggleBackToUnanswered() {
        var d = EntryValuesDraft()
        d.setBool(true, for: "b")
        XCTAssertEqual(d.bool(for: "b"), true)
        d.setBool(true, for: "b")
        XCTAssertNil(d.bool(for: "b"))
    }

    func testACommaDecimalIsAcceptedWhereTheLocaleTypesOne() {
        let n = TrackerFieldInfo(id: "n", label: "N", kind: .number, unit: nil, options: [])
        var d = EntryValuesDraft(["n": .number(98.6)], locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(d.numberText(for: "n"), "98,6", "shown back as the locale writes it")
        XCTAssertEqual(d.sent(for: [n]), ["n": .number(98.6)])
        d.setNumberText("37,5", for: "n")
        XCTAssertEqual(d.sent(for: [n]), ["n": .number(37.5)])
        XCTAssertEqual(d.problems(for: [n], requireAll: true), [])
        d.setNumberText("37.5", for: "n")
        XCTAssertEqual(d.sent(for: [n]), ["n": .number(37.5)], "a point is still a decimal point")
        d.setNumberText("1.000,5", for: "n")
        XCTAssertEqual(d.problems(for: [n], requireAll: false), ["N: enter a number."])
    }

    func testACommaIsNotADecimalWhereTheLocaleDoesNotTypeOne() {
        let n = TrackerFieldInfo(id: "n", label: "N", kind: .number, unit: nil, options: [])
        var d = EntryValuesDraft([:], locale: Locale(identifier: "en_US"))
        d.setNumberText("37,5", for: "n")
        XCTAssertEqual(d.problems(for: [n], requireAll: false), ["N: enter a number."])
        XCTAssertEqual(EntryValuesDraft.number("37,5", separator: ","), 37.5)
        XCTAssertNil(EntryValuesDraft.number("37,5"))
    }

    func testISOTimesParseWithAndWithoutFractionalSeconds() {
        let at = ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z")!
        XCTAssertEqual(EntryValuesDraft.parseISO("2026-11-07T18:00:00-06:00"), at)
        XCTAssertEqual(EntryValuesDraft.parseISO("2026-11-08T00:00:00.000Z"), at)
        XCTAssertNil(EntryValuesDraft.parseISO("yesterday"))
    }

    func testADateIsSentInTheReceiversOffset() {
        var d = EntryValuesDraft()
        let chicago = TimeZone(identifier: "America/Chicago")!
        let at = ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z")!
        d.setDate(at, for: "d", zone: chicago)
        XCTAssertEqual(d.text(for: "d"), "2026-11-07T18:00:00-06:00")
        XCTAssertEqual(d.date(for: "d"), at)
    }
}
