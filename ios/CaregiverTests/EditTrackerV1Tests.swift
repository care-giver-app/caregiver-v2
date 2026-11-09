import XCTest
@testable import Caregiver

/// Edit tracker, Pause this tracker? and Resume on `/v1` (PRD "Edit tracker", "Pause this
/// tracker?", "Tracker detail"), against closure-stubbed services.
@MainActor
final class EditTrackerV1Tests: XCTestCase {
    private let admin = TeamReceiver(id: "receiver-eleanor", name: "Eleanor",
                                     timeZone: TimeZone(identifier: "America/Chicago")!, canManage: true)
    private let caregiver = TeamReceiver(id: "receiver-eleanor", name: "Eleanor",
                                         timeZone: TimeZone(identifier: "America/Chicago")!, canManage: false)

    private struct Boom: Error {}

    /// Medication with a paused third field, as Edit tracker opens on it.
    private var medication: TrackerProfile {
        let m = TrackersFixtures.medication
        return TrackerProfile(
            id: m.id, name: m.name, icon: m.icon, color: m.color, status: .active, pausedAt: nil,
            fields: m.fields + [TrackerFieldInfo(id: "food", label: "Taken with food", kind: .boolean,
                                                 unit: nil, paused: true, options: [])],
            gapHours: nil, scheduleCount: 2, lastLoggedAt: nil, attention: []
        )
    }

    private func model(_ profile: TrackerProfile? = nil, receiver: TeamReceiver? = nil,
                       schedules: [TrackerScheduleItem] = TrackersFixtures.medicationSchedules,
                       edits: Recorder<(TrackerWrite, Bool)> = Recorder(),
                       conflictUnlessConfirmed: Bool = false,
                       pauses: Recorder<String> = Recorder()) -> EditTrackerV1Model {
        var service = TrackersFixtures.service()
        service.listSchedules = { _ in schedules }
        service.editTracker = { id, w, remove in
            await edits.record((w, remove))
            if conflictUnlessConfirmed && !remove { throw SchedulesOrGapConflict(message: "both") }
            return TrackersFixtures.profile(id: id, from: w)
        }
        service.pauseTracker = { id in
            await pauses.record(id)
            return TrackersFixtures.walk.with(status: .paused)
        }
        return EditTrackerV1Model(profile: profile ?? medication, receiver: receiver ?? admin, service: service)
    }

    // MARK: Opening

    func testOpensOnTheTrackerAsItIs() async {
        let m = model()
        XCTAssertEqual(m.draft.name, "Medication")
        XCTAssertEqual(m.draft.fields.map(\.fieldID), ["given", "dose", "food"])
        XCTAssertEqual(m.draft.fields.map(\.paused), [false, false, true])
        XCTAssertFalse(m.gapOn)
        XCTAssertEqual(m.schedules, .loading)
        await m.loadSchedules()
        XCTAssertEqual(m.schedules, .loaded(TrackersFixtures.medicationSchedules))
    }

    func testAGapOpensInDaysWhenWholeDaysElseHours() {
        XCTAssertEqual(model(TrackersFixtures.weight).gapAmount, "7")
        XCTAssertEqual(model(TrackersFixtures.weight).gapUnit, .days)
        let odd = TrackersFixtures.profile(id: "x", from: TrackerWrite(name: "X", icon: "heart", color: "#1c8fe0",
                                                                         fields: [], gapHours: 36))
        let m = model(odd)
        XCTAssertTrue(m.gapOn)
        XCTAssertEqual(m.gapAmount, "36")
        XCTAssertEqual(m.gapUnit, .hours)
    }

    // MARK: Save

    func testSaveSendsNameFieldsAndGapKeepingIdsPausedFieldsAndOrder() async {
        let edits = Recorder<(TrackerWrite, Bool)>()
        let m = model(schedules: [], edits: edits)
        await m.loadSchedules()
        m.draft.name = "  Meds  "
        m.setCollecting(m.draft.fields[1].id, false)
        var added = m.newField()
        added.label = "Note"
        m.save(added)
        let saved = await m.save()
        XCTAssertNotNil(saved)
        let sent = await edits.values
        XCTAssertEqual(sent.count, 1)
        let (w, remove) = sent[0]
        XCTAssertFalse(remove)
        XCTAssertEqual(w.name, "Meds")
        XCTAssertEqual(w.fields.map(\.fieldID), ["given", "dose", "food", nil])
        XCTAssertEqual(w.fields.map(\.label), ["Given", "Dose", "Taken with food", "Note"])
        XCTAssertEqual(w.fields.map(\.paused), [false, true, true, false])
        XCTAssertNil(w.gapHours)
    }

    func testChangingAFieldReplacesItInPlace() {
        let m = model()
        var dose = m.draft.fields[1]
        dose.required = true
        m.save(dose)
        XCTAssertEqual(m.draft.fields.count, 3)
        XCTAssertTrue(m.draft.fields[1].required)
        XCTAssertEqual(m.draft.fields[1].fieldID, "dose")
    }

    func testGapIsSentInHours() async {
        let edits = Recorder<(TrackerWrite, Bool)>()
        let m = model(TrackersFixtures.weight, schedules: [], edits: edits)
        await m.loadSchedules()
        m.gapAmount = "2"
        m.gapUnit = .days
        _ = await m.save()
        m.gapUnit = .hours
        m.gapAmount = "12"
        _ = await m.save()
        m.gapOn = false
        _ = await m.save()
        let sent = await edits.values.map(\.0.gapHours)
        XCTAssertEqual(sent, [48, 12, nil])
    }

    func testProblemsHoldSave() async {
        let edits = Recorder<(TrackerWrite, Bool)>()
        let m = model(schedules: [], edits: edits)
        m.draft.name = " "
        XCTAssertFalse(m.canSave)
        XCTAssertTrue(m.problems.contains("Give the tracker a name."))
        m.draft.name = "Medication"
        m.gapOn = true
        m.gapAmount = ""
        XCTAssertEqual(m.problems, ["Say how long the longest gap is."])
        m.gapAmount = "0"
        XCTAssertEqual(m.problems, ["A gap must be at least 1 hour."])
        let saved = await m.save()
        XCTAssertNil(saved)
        let sent = await edits.values
        XCTAssertTrue(sent.isEmpty)
    }

    func testCancelSendsNothing() async {
        // Cancel is the sheet dismissing: the model is dropped without Save.
        let edits = Recorder<(TrackerWrite, Bool)>()
        let m = model(edits: edits)
        m.draft.name = "Changed"
        m.gapOn = true
        let sent = await edits.values
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: Schedules or a gap

    func testTurningTheGapOnOverSchedulesAsksBeforeSendingThenRemovesThem() async {
        let edits = Recorder<(TrackerWrite, Bool)>()
        let m = model(edits: edits)
        await m.loadSchedules()
        m.gapOn = true
        m.gapAmount = "1"
        XCTAssertEqual(m.schedulesLostToGap.map(\.name), ["Morning", "Evening", "Lisinopril refill — Mon, every month"])
        let first = await m.save()
        XCTAssertNil(first)
        XCTAssertEqual(m.pendingRemoval?.count, 3)
        var sent = await edits.values
        XCTAssertTrue(sent.isEmpty)

        let saved = await m.confirmRemoval()
        XCTAssertNotNil(saved)
        XCTAssertNil(m.pendingRemoval)
        sent = await edits.values
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].1)
        XCTAssertEqual(sent[0].0.gapHours, 24)
    }

    func testCancellingTheRemovalSendsNothing() async {
        let edits = Recorder<(TrackerWrite, Bool)>()
        let m = model(edits: edits)
        await m.loadSchedules()
        m.gapOn = true
        m.gapAmount = "1"
        _ = await m.save()
        m.cancelRemoval()
        XCTAssertNil(m.pendingRemoval)
        let sent = await edits.values
        XCTAssertTrue(sent.isEmpty)
    }

    func testAConflictFromTheServerAsksThenResendsConfirmed() async {
        // The schedules couldn't be read, so the server's 409 is what asks.
        let edits = Recorder<(TrackerWrite, Bool)>()
        var service = TrackersFixtures.service()
        service.listSchedules = { _ in throw Boom() }
        service.editTracker = { id, w, remove in
            await edits.record((w, remove))
            if !remove { throw SchedulesOrGapConflict(message: "both") }
            return TrackersFixtures.profile(id: id, from: w)
        }
        let m = EditTrackerV1Model(profile: medication, receiver: admin, service: service)
        await m.loadSchedules()
        m.gapOn = true
        m.gapAmount = "3"
        let first = await m.save()
        XCTAssertNil(first)
        XCTAssertEqual(m.pendingRemoval, [])
        XCTAssertNil(m.saveFailed)
        let saved = await m.confirmRemoval()
        XCTAssertNotNil(saved)
        let sent = await edits.values.map(\.1)
        XCTAssertEqual(sent, [false, true])
    }

    func testAFailedSaveStaysWithTheDraft() async {
        var service = TrackersFixtures.service()
        service.listSchedules = { _ in [] }
        service.editTracker = { _, _, _ in throw Boom() }
        let m = EditTrackerV1Model(profile: medication, receiver: admin, service: service)
        await m.loadSchedules()
        m.draft.name = "Meds"
        let saved = await m.save()
        XCTAssertNil(saved)
        XCTAssertNotNil(m.saveFailed)
        XCTAssertEqual(m.draft.name, "Meds")
    }

    // MARK: Pause

    func testPauseCallsTheService() async {
        let pauses = Recorder<String>()
        let m = model(pauses: pauses)
        let paused = await m.pause()
        XCTAssertTrue(paused)
        let sent = await pauses.values
        XCTAssertEqual(sent, ["medication"])
    }

    func testAFailedPauseSaysSo() async {
        var service = TrackersFixtures.service()
        service.pauseTracker = { _ in throw Boom() }
        let m = EditTrackerV1Model(profile: medication, receiver: admin, service: service)
        let paused = await m.pause()
        XCTAssertFalse(paused)
        XCTAssertNotNil(m.pauseFailed)
    }

    func testPauseIsOfferedOnlyOnAnActiveTrackerToAnAdmin() {
        XCTAssertTrue(model().canPause)
        XCTAssertFalse(model(TrackersFixtures.walk).canPause)
        XCTAssertFalse(model(receiver: caregiver).canPause)
        XCTAssertTrue(model().canEdit)
        XCTAssertFalse(model(receiver: caregiver).canEdit)
    }

    func testPauseGoesBackToTheLastTrackersList() {
        let trackers = V1Route.trackers(admin)
        let detail = V1Route.tracker(id: "medication", receiver: admin)
        let schedules = V1Route.schedules(trackerID: "medication", trackerName: "Medication", receiver: admin)
        XCTAssertEqual(V1Route.poppedToTrackers([trackers, detail]), [trackers])
        XCTAssertEqual(V1Route.poppedToTrackers([trackers, detail, schedules]), [trackers])
        XCTAssertEqual(V1Route.poppedToTrackers([detail]), [])
    }

    // MARK: Resume, on Tracker detail

    func testResumeReloadsTheDetailAsActive() async {
        let walk = TrackersFixtures.walk
        let reads = Recorder<String>()
        let resumed = Box(false)
        var service = TrackersFixtures.service()
        service.trackerDetail = { id in
            await reads.record(id)
            return await resumed.value ? walk.with(status: .active) : walk
        }
        service.resumeTracker = { _ in
            await resumed.set(true)
            return walk.with(status: .active)
        }
        let m = TrackerDetailV1Model(trackerID: "walk", receiver: admin, service: service)
        await m.load()
        XCTAssertTrue(m.canResume)
        XCTAssertTrue(m.canEdit)
        await m.resume()
        XCTAssertEqual(m.profile?.status, .active)
        XCTAssertFalse(m.canResume)
        let count = await reads.values.count
        XCTAssertEqual(count, 2)
    }

    func testAFailedResumeStaysPaused() async {
        var service = TrackersFixtures.service()
        service.resumeTracker = { _ in throw Boom() }
        let m = TrackerDetailV1Model(trackerID: "walk", receiver: admin, service: service)
        await m.load()
        await m.resume()
        XCTAssertEqual(m.profile?.status, .paused)
        XCTAssertNotNil(m.resumeFailed)
    }

    func testCaregiversSeeNeitherResumeNorEdit() async {
        let m = TrackerDetailV1Model(trackerID: "walk", receiver: caregiver, service: TrackersFixtures.service())
        await m.load()
        XCTAssertEqual(m.profile?.status, .paused)
        XCTAssertFalse(m.canResume)
        XCTAssertFalse(m.canEdit)
    }

    func testResumeSaysWhatStartsAgain() {
        XCTAssertEqual(TrackerText.resumeExplanation(TrackersFixtures.walk),
                       "Once resumed, the team can log it again.")
        let medication = TrackersFixtures.medication
        XCTAssertEqual(TrackerText.resumeExplanation(medication),
                       "Once resumed, the team can log it again and its 2 schedules start again from now.")
    }
}

private actor Recorder<T: Sendable> {
    private(set) var values: [T] = []
    func record(_ v: T) { values.append(v) }
}

private actor Box<T: Sendable> {
    var value: T
    init(_ value: T) { self.value = value }
    func set(_ v: T) { value = v }
}
