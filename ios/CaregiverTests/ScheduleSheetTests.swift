import XCTest
@testable import Caregiver

/// A schedule and Remove this schedule? on `/v1` (PRD "A schedule", "Remove this
/// schedule?"), against closure-stubbed services.
@MainActor
final class ScheduleSheetTests: XCTestCase {
    private let eleanor = TrackersFixtures.eleanor
    /// 2026-11-09 18:00 UTC: noon in Chicago, Monday.
    private let now = Date(timeIntervalSince1970: 1_794_247_200)

    private struct Boom: Error {}

    /// Medication with a number, a text, a retired option and a paused field, so every
    /// kind of pre-fill is in play.
    private let fields: [TrackerFieldInfo] = [
        TrackerFieldInfo(id: "given", label: "Given", kind: .boolean, unit: nil, options: []),
        TrackerFieldInfo(id: "dose", label: "Dose", kind: .choice, unit: nil, options: [
            ChoiceOptionInfo(id: "lis10", label: "Lisinopril 10 mg", retired: false),
            ChoiceOptionInfo(id: "lis5", label: "Lisinopril 5 mg", retired: true),
            ChoiceOptionInfo(id: "lis20", label: "Lisinopril 20 mg", retired: false),
        ]),
        TrackerFieldInfo(id: "mg", label: "Amount", kind: .number, unit: "mg", options: []),
        TrackerFieldInfo(id: "note", label: "Note", kind: .text, unit: nil, options: []),
        TrackerFieldInfo(id: "food", label: "With food", kind: .boolean, unit: nil, paused: true, options: []),
    ]

    private func model(existing: TrackerScheduleItem? = nil, replacesGap: Bool = false,
                       calls: Recorder<String> = Recorder(), conflictUnlessReplacing: Bool = false,
                       failing: Bool = false,
                       adds: WriteLog = WriteLog()) -> ScheduleSheetModel {
        var service = TrackersFixtures.service()
        service.addSchedule = { id, w, replace in
            await adds.add(w, replace)
            if failing { throw Boom() }
            if conflictUnlessReplacing && !replace { throw SchedulesOrGapConflict(message: "gap") }
            return TrackersFixtures.schedule(id: "new", from: w)
        }
        service.changeSchedule = { id, w in
            await adds.change(id, w)
            if failing { throw Boom() }
            return TrackersFixtures.schedule(id: id, from: w)
        }
        service.removeSchedule = { id in
            await calls.record(id)
            if failing { throw Boom() }
        }
        let now = self.now
        return ScheduleSheetModel(trackerID: "medication", trackerName: "Medication", trackerIcon: "pills",
                                  trackerColor: TrackersFixtures.violet, fields: fields, receiver: eleanor,
                                  existing: existing, replacesGap: replacesGap, gapHours: 168,
                                  service: service, now: { now })
    }

    // MARK: New

    func testANewScheduleStartsBlankEveryWeekAtEightWithTheAlertOn() {
        let m = model()
        XCTAssertTrue(m.isNew)
        XCTAssertEqual(m.draft.days, [])
        XCTAssertEqual(m.draft.interval, 1)
        XCTAssertEqual(m.draft.time, "08:00")
        XCTAssertNil(m.draft.endsOn)
        XCTAssertTrue(m.draft.unrecordedAlert)
        XCTAssertEqual(m.fields.map(\.id), ["given", "dose", "mg", "note"], "paused fields take no pre-fill")
        XCTAssertNil(m.derivedName)
    }

    func testNewScheduleSendsTheRuleAndOnlyActiveFieldsPrefilled() async {
        let log = WriteLog()
        let m = model(adds: log)
        m.toggle(.mo)
        m.toggle(.fr)
        m.toggle(.we)
        m.draft.interval = 2
        m.draft.time = "20:30"
        m.draft.endsOn = LocalDay(year: 2026, month: 12, day: 31)
        m.setBool(true, for: "given")
        m.choose("lis20", in: fields[1])
        m.setNumberText("10", for: "mg")
        m.setText("  ", for: "note")
        m.draft.plannedValues["food"] = .bool(true)
        m.draft.label = "   "

        let outcome = await m.save()

        let adds = await log.adds
        XCTAssertEqual(adds.count, 1)
        let (w, replace) = adds[0]
        XCTAssertFalse(replace)
        XCTAssertNil(w.label, "a blank label lets the server derive the name")
        XCTAssertEqual(w.days, [.mo, .we, .fr])
        XCTAssertEqual(w.interval, 2)
        XCTAssertEqual(w.time, "20:30")
        XCTAssertEqual(w.endsOn, LocalDay(year: 2026, month: 12, day: 31))
        XCTAssertEqual(w.plannedValues, ["given": .bool(true), "dose": .list(["lis20"]), "mg": .number(10)])
        XCTAssertTrue(w.unrecordedAlert)
        guard case .saved(_, replacedGap: false) = outcome else { return XCTFail("\(String(describing: outcome))") }
    }

    func testTheDerivedNameMirrorsTheServers() {
        let m = model()
        m.toggle(.mo)
        XCTAssertEqual(m.derivedName, "Mon at 8:00 AM")
        ScheduleWeekday.allCases.forEach { if $0 != .mo { m.toggle($0) } }
        m.draft.time = "21:00"
        XCTAssertEqual(m.derivedName, "Every day at 9:00 PM")
        m.draft.interval = 2
        XCTAssertEqual(m.derivedName, "Every 2 weeks: every day at 9:00 PM")
    }

    func testASingleChoiceReplacesAndChoosingItAgainClears() {
        let m = model()
        m.choose("lis10", in: fields[1])
        m.choose("lis20", in: fields[1])
        XCTAssertEqual(m.chosen(for: "dose"), ["lis20"])
        m.choose("lis20", in: fields[1])
        XCTAssertNil(m.draft.plannedValues["dose"])
        m.setBool(false, for: "given")
        m.setBool(false, for: "given")
        XCTAssertNil(m.bool(for: "given"))
    }

    // MARK: The gap

    func testTheFirstScheduleOnAGapTrackerReplacesTheGapDirectly() async {
        let log = WriteLog()
        let m = model(replacesGap: true, adds: log)
        m.toggle(.mo)
        let outcome = await m.save()
        let adds = await log.adds
        XCTAssertEqual(adds.map(\.1), [true])
        guard case .saved(_, replacedGap: true) = outcome else { return XCTFail("\(String(describing: outcome))") }
    }

    func testAConflictAsksThenResendsReplacingTheGap() async {
        let log = WriteLog()
        let m = model(conflictUnlessReplacing: true, adds: log)
        m.toggle(.tu)
        let first = await m.save()
        XCTAssertNil(first)
        XCTAssertTrue(m.confirmingGap)
        XCTAssertNil(m.saveFailed)
        let second = await m.confirmReplaceGap()
        XCTAssertFalse(m.confirmingGap)
        let adds = await log.adds
        XCTAssertEqual(adds.map(\.1), [false, true])
        guard case .saved(_, replacedGap: true) = second else { return XCTFail("\(String(describing: second))") }
    }

    // MARK: Existing

    func testAnExistingScheduleOpensAsSavedAndChangesInPlace() async {
        let log = WriteLog()
        let evening = TrackerScheduleItem(id: "s2", name: "Evening", label: "Evening", days: [.mo, .tu],
                                          interval: 4, time: "20:00",
                                          plannedValues: ["dose": .list(["lis10"]), "mg": .number(12.5)],
                                          unrecordedAlert: true)
        let m = model(existing: evening, adds: log)
        XCTAssertFalse(m.isNew)
        XCTAssertEqual(m.draft.label, "Evening")
        XCTAssertEqual(m.numberText["mg"], "12.5")
        XCTAssertEqual(m.chosen(for: "dose"), ["lis10"])
        m.draft.unrecordedAlert = false

        let outcome = await m.save()

        let changes = await log.changes
        let adds = await log.adds
        XCTAssertTrue(adds.isEmpty)
        XCTAssertEqual(changes.map(\.0), ["s2"])
        XCTAssertEqual(changes.first?.1.label, "Evening")
        XCTAssertEqual(changes.first?.1.interval, 4)
        XCTAssertEqual(changes.first?.1.unrecordedAlert, false)
        guard case .saved(let s, replacedGap: false) = outcome else { return XCTFail() }
        XCTAssertEqual(s.id, "s2")
    }

    func testAFailedSaveStaysWithTheMessage() async {
        let m = model(failing: true)
        m.toggle(.mo)
        let outcome = await m.save()
        XCTAssertNil(outcome)
        XCTAssertNotNil(m.saveFailed)
        XCTAssertFalse(m.isSaving)
    }

    // MARK: Problems

    func testProblemsBlockSave() async {
        let log = WriteLog()
        let m = model(adds: log)
        XCTAssertEqual(m.problems, ["Choose at least one day."])
        XCTAssertFalse(m.canSave)
        m.toggle(.mo)
        XCTAssertTrue(m.canSave)
        m.setNumberText("ten", for: "mg")
        XCTAssertEqual(m.problems, ["Amount: enter a number, or leave it blank."])
        m.setNumberText("", for: "mg")
        m.draft.endsOn = LocalDay(year: 2026, month: 11, day: 8)
        XCTAssertEqual(m.problems, ["The end date can't be before today."])
        m.draft.endsOn = LocalDay(year: 2026, month: 11, day: 9)
        XCTAssertTrue(m.problems.isEmpty, "today is the receiver's date")
        m.draft.endsOn = LocalDay(year: 2026, month: 11, day: 8)
        let outcome = await m.save()
        XCTAssertNil(outcome)
        let adds = await log.adds
        XCTAssertTrue(adds.isEmpty)
    }

    // MARK: Remove

    func testRemoveRemovesTheSchedule() async {
        let calls = Recorder<String>()
        let m = model(existing: TrackersFixtures.medicationSchedules[1], calls: calls)
        XCTAssertEqual(m.displayName, "Evening")
        let removed = await m.remove()
        XCTAssertTrue(removed)
        let ids = await calls.values
        XCTAssertEqual(ids, ["s2"])
    }

    func testAFailedRemoveStays() async {
        let m = model(existing: TrackersFixtures.medicationSchedules[1], failing: true)
        let removed = await m.remove()
        XCTAssertFalse(removed)
        XCTAssertNotNil(m.removeFailed)
    }

    func testANewScheduleHasNothingToRemove() async {
        let calls = Recorder<String>()
        let m = model(calls: calls)
        let removed = await m.remove()
        XCTAssertFalse(removed)
        let ids = await calls.values
        XCTAssertTrue(ids.isEmpty)
    }

    // MARK: From Edit tracker

    func testFromEditTrackerAGapTrackerWithNoSchedulesWarnsAndRemoveReloads() async {
        var service = TrackersFixtures.service()
        let listed = Recorder<String>()
        service.listSchedules = { id in
            await listed.record(id)
            return []
        }
        let edit = EditTrackerV1Model(profile: TrackersFixtures.weight, receiver: eleanor, service: service)
        await edit.loadSchedules()
        let new = ScheduleSheetModel(editing: edit, target: .new)
        XCTAssertTrue(new.replacesGap)
        XCTAssertEqual(new.gapHours, 168)
        XCTAssertEqual(new.trackerName, "Weight")

        let existing = ScheduleSheetModel(editing: edit, target: .existing(TrackersFixtures.medicationSchedules[0]))
        XCTAssertFalse(existing.replacesGap, "only a new schedule replaces the gap")

        let withSchedules = EditTrackerV1Model(profile: TrackersFixtures.medication, receiver: eleanor,
                                               service: TrackersFixtures.service())
        await withSchedules.loadSchedules()
        XCTAssertFalse(ScheduleSheetModel(editing: withSchedules, target: .new).replacesGap)
    }

    func testCopySaysWhatGoesAndWhatStays() {
        let remove = RemoveScheduleV1Sheet.explanation
        XCTAssertTrue(remove.contains("every occurrence of it still waiting"))
        XCTAssertTrue(remove.contains("logged, skipped, or unrecorded"))
        let pause = PauseTrackerV1Sheet.explanation
        for part in ["Nothing new can be logged", "schedules stop", "thresholds stop alerting",
                     "Home and the logging picker", "occurrences already waiting go", "Every entry ever logged"] {
            XCTAssertTrue(pause.contains(part), part)
        }
    }
}

private actor Recorder<T: Sendable> {
    private(set) var values: [T] = []
    func record(_ v: T) { values.append(v) }
}

private actor WriteLog {
    private(set) var adds: [(ScheduleWrite, Bool)] = []
    private(set) var changes: [(String, ScheduleWrite)] = []
    func add(_ w: ScheduleWrite, _ replace: Bool) { adds.append((w, replace)) }
    func change(_ id: String, _ w: ScheduleWrite) { changes.append((id, w)) }
}
