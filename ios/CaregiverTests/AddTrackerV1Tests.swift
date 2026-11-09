import XCTest
@testable import Caregiver

/// Add tracker on `/v1` (PRD "Add tracker"), against closure-stubbed services.
@MainActor
final class AddTrackerV1Tests: XCTestCase {
    private let receiver = TeamReceiver(id: "receiver-eleanor", name: "Eleanor",
                                        timeZone: TimeZone(identifier: "America/Chicago")!, canManage: true)
    private var weight: TrackerTemplate { TrackersFixtures.templates.first { $0.id == "weight" }! }
    private var shower: TrackerTemplate { TrackersFixtures.templates.first { $0.id == "shower" }! }
    private var doctor: TrackerTemplate { TrackersFixtures.templates.first { $0.id == "doctor_appointment" }! }

    private struct Boom: Error {}

    private func model(templates: @escaping @Sendable () async throws -> [TrackerTemplate] = { TrackersFixtures.templates },
                       add: @escaping @Sendable (String, TrackerWrite) async throws -> TrackerProfile = { _, w in
                           TrackersFixtures.profile(id: "new-tracker", from: w)
                       }) -> AddTrackerV1Model {
        var service = TrackersFixtures.service()
        service.listTemplates = templates
        service.addTracker = add
        return AddTrackerV1Model(receiver: receiver, service: service)
    }

    // MARK: Templates

    func testTemplatesLoadInServedOrder() async {
        let m = model()
        XCTAssertEqual(m.templates, .loading)
        XCTAssertEqual(m.part, .choose)
        await m.loadTemplates()
        XCTAssertEqual(m.templates, .loaded(TrackersFixtures.templates))
    }

    func testTemplatesFailThenRetry() async {
        let fail = Flag(true)
        let m = model(templates: {
            if await fail.value { throw Boom() }
            return TrackersFixtures.templates
        })
        await m.loadTemplates()
        guard case .failed = m.templates else { return XCTFail("expected failed, got \(m.templates)") }
        await fail.set(false)
        await m.retryTemplates()
        XCTAssertEqual(m.templates, .loaded(TrackersFixtures.templates))
    }

    // MARK: Choosing

    func testChoosingATemplateFillsTheSecondPart() {
        let m = model()
        m.choose(weight)
        XCTAssertEqual(m.part, .adjust)
        XCTAssertEqual(m.draft.name, "Weight")
        XCTAssertEqual(m.draft.icon, "scalemass")
        XCTAssertEqual(m.draft.color, "#4F8EF7")
        XCTAssertEqual(m.draft.fields.map(\.label), ["Weight"])
        XCTAssertEqual(m.draft.fields.first?.rowSummary, "Number · required")
    }

    func testATemplatesGapIsCarriedWithoutBeingShown() {
        let m = model()
        m.choose(shower)
        XCTAssertEqual(m.draft.gapHours, 72)
        XCTAssertEqual(m.draft.write.gapHours, 72)
    }

    func testStartFromScratchIsEmpty() {
        let m = model()
        m.startFromScratch()
        XCTAssertEqual(m.part, .adjust)
        XCTAssertEqual(m.draft, .scratch(icon: AddTrackerV1Model.scratchIcon, color: AddTrackerV1Model.scratchColor))
        XCTAssertEqual(m.problems, ["Give the tracker a name."])
        XCTAssertFalse(m.canCreate)
    }

    func testBackKeepsTheDraftUntilAnotherTemplateReplacesIt() {
        let m = model()
        m.choose(weight)
        m.draft.name = "Mom's weight"
        m.back()
        XCTAssertEqual(m.part, .choose)
        XCTAssertEqual(m.draft.name, "Mom's weight", "Back alone loses nothing")
        m.choose(doctor)
        XCTAssertEqual(m.draft.name, "Doctor Appointment")
        XCTAssertEqual(m.draft.fields.count, 6)
        m.back()
        m.startFromScratch()
        XCTAssertTrue(m.draft.fields.isEmpty)
    }

    // MARK: Fields

    func testRemoveAddAndEditFields() {
        let m = model()
        m.choose(doctor)
        let specialty = m.draft.fields[1]
        m.remove(specialty.id)
        XCTAssertFalse(m.draft.fields.map(\.label).contains("Specialty"))

        var added = FieldDraft.blank()
        added.label = "Copay"
        added.kind = .number
        added.unit = "$"
        m.draft.upsert(added)
        XCTAssertEqual(m.draft.fields.last?.label, "Copay")
        XCTAssertEqual(m.draft.fields.count, 6)

        var doctorField = m.draft.fields[0]
        doctorField.required = false
        doctorField.label = "Doctor's name"
        m.draft.upsert(doctorField)
        XCTAssertEqual(m.draft.fields[0].label, "Doctor's name", "saved in place, by id")
        XCTAssertEqual(m.draft.fields.count, 6)

        m.remove(added.id)
        XCTAssertEqual(m.draft.fields.count, 5)
    }

    func testRemovingAFieldNeverSavedChangesNothing() {
        let m = model()
        m.choose(weight)
        m.remove(FieldDraft.blank().id)
        XCTAssertEqual(m.draft.fields.count, 1)
    }

    // MARK: Create

    func testCreateSendsTheDraftForTheReceiverAndReturnsTheTracker() async {
        let sent = Box<(String, TrackerWrite)?>(nil)
        let m = model(add: { id, w in
            await sent.set((id, w))
            return TrackersFixtures.profile(id: "trk-42", from: w)
        })
        m.choose(doctor)
        m.draft.name = "  Dr. Patel  "
        m.remove(m.draft.fields[1].id)

        let made = await m.create()

        XCTAssertEqual(made?.id, "trk-42")
        let got = await sent.value
        XCTAssertEqual(got?.0, "receiver-eleanor")
        XCTAssertEqual(got?.1, TrackerWrite(name: "Dr. Patel", icon: "stethoscope", color: "#0891B2",
                                            fields: m.draft.fields.map(\.write), gapHours: nil))
        XCTAssertEqual(got?.1.fields.map(\.label), ["Doctor", "Location", "Reason", "Outcome", "Follow-up"])
        XCTAssertFalse(m.isCreating)
        XCTAssertNil(m.createFailed)
    }

    func testCreateFailureKeepsTheSheetAndTheDraft() async {
        let m = model(add: { _, _ in throw Boom() })
        m.choose(weight)
        let before = m.draft
        let made = await m.create()
        XCTAssertNil(made)
        XCTAssertNotNil(m.createFailed)
        XCTAssertEqual(m.part, .adjust)
        XCTAssertEqual(m.draft, before)
        XCTAssertFalse(m.isCreating)
    }

    func testCreateWithProblemsSendsNothing() async {
        let calls = Box(0)
        let m = model(add: { _, w in
            await calls.set(1)
            return TrackersFixtures.profile(id: "x", from: w)
        })
        m.startFromScratch()
        let made = await m.create()
        XCTAssertNil(made)
        let n = await calls.value
        XCTAssertEqual(n, 0)
    }
}

private actor Box<T: Sendable> {
    var value: T
    init(_ value: T) { self.value = value }
    func set(_ v: T) { value = v }
}

private actor Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
    func set(_ v: Bool) { value = v }
}
