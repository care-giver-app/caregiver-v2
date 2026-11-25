import XCTest
import CaregiverAPI
@testable import Caregiver

private typealias S = Components.Schemas

/// Fixed instants, people and zones: nothing here reads the device zone or the network.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Tuesday Nov 10 2026, 2:00 PM in Chicago.
    static let now = at("2026-11-10T20:00:00Z")
    static let nov10 = LocalDay(year: 2026, month: 11, day: 10)

    static let admin = TeamReceiver(id: "eleanor", name: "Eleanor", timeZone: chicago, canManage: true)
    static let caregiver = TeamReceiver(id: "eleanor", name: "Eleanor", timeZone: chicago, canManage: false)

    static let trevor = TeamMemberInfo(userID: "trevor", name: "Trevor", role: .admin)
    static let dana = TeamMemberInfo(userID: "dana", name: "Dana", role: .admin)
    static let marcus = TeamMemberInfo(userID: "marcus", name: "Marcus", role: .caregiver)
    static let members = [trevor, dana, marcus]

    static func detail(archived: Bool = false, instructions: CareInstructionsInfo? = nil,
                       contacts: [EmergencyContactInfo] = []) -> CareReceiverInfo {
        CareReceiverInfo(id: "eleanor", teamID: "riverside", teamName: "The Riverside Group", name: "Eleanor",
                         timeZone: chicago, isArchived: archived, archivedByName: archived ? "Dana" : nil,
                         archivedAt: archived ? now : nil, instructions: instructions, contacts: contacts)
    }

    static let dana555 = EmergencyContactInfo(id: "c-dana", name: "Dana", relationship: "Daughter",
                                              phone: "(555) 014-2277")
    static let ahn = EmergencyContactInfo(id: "c-ahn", name: "Dr. Ahn", relationship: "Primary care",
                                          phone: "(555) 019-9040")

    static func local(_ s: String) -> LocalDateTime { LocalDateTime(s)! }

    static func assignment(_ id: String, _ who: TeamMemberInfo, _ starts: String, _ ends: String,
                           rule: String? = nil) -> AssignmentInfo {
        AssignmentInfo(id: id, receiverID: "eleanor", userID: who.userID, caregiverName: who.name,
                       starts: local(starts), ends: local(ends), startsAt: now, endsAt: now,
                       coverageScheduleID: rule)
    }

    static let thursday = assignment("thu", dana, "2026-11-12T08:00", "2026-11-12T16:00", rule: "rule-dana")
    static let tuesdayRule = CoverageScheduleInfo(id: "rule-trevor", receiverID: "eleanor", userID: "trevor",
                                                  caregiverName: "Trevor", days: [.tu], interval: 1,
                                                  startTime: "08:00", endTime: "16:00", startsOn: nov10, endsOn: nil)

    /// Eleanor's detail, a roster, and the Riverside team's members.
    static func service(detail: CareReceiverInfo = detail(), onDuty: [AssignmentInfo] = [],
                        assignments: [AssignmentInfo] = [thursday],
                        coverage: [CoverageScheduleInfo] = [tuesdayRule]) -> TeamService {
        var s = TeamService()
        s.careReceiver = { _ in detail }
        s.onDuty = { _ in onDuty }
        s.assignments = { _ in assignments }
        s.coverageSchedules = { _ in coverage }
        s.team = { _ in TeamDetailInfo(teamID: "riverside", name: "The Riverside Group", myRole: .admin,
                                       members: members) }
        return s
    }
}

private struct Down: Error {}

/// Records what the closures were handed.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [T] = []
    func add(_ v: T) { lock.withLock { values.append(v) } }
    var all: [T] { lock.withLock { values } }
}

// MARK: - Mapping

final class CareReceiverMappingTests: XCTestCase {
    func testADetailKeepsItsContactsInTheAdminsOrderAndSaysWhenArchived() {
        let info = CareReceiverInfo(S.CareReceiverDetail(
            receiverId: "eleanor", teamId: "riverside", teamName: "The Riverside Group", name: "Eleanor",
            timeZone: "America/Chicago", status: .archived, archivedByName: "Dana", archivedAt: Fixed.now,
            careInstructions: .init(body: "Pills with food.", updatedByName: "a former caregiver",
                                    updatedAt: Fixed.now),
            emergencyContacts: [.init(contactId: "2", name: "Dr. Ahn", relationship: "", phone: "555"),
                                .init(contactId: "1", name: "Dana", relationship: "Daughter", phone: "556")]))
        XCTAssertTrue(info.isArchived)
        XCTAssertEqual(info.archivedByName, "Dana")
        XCTAssertEqual(info.timeZone, Fixed.chicago)
        XCTAssertEqual(info.instructions?.updatedByName, "a former caregiver")
        XCTAssertEqual(info.contacts.map(\.id), ["2", "1"])
    }

    func testAnAssignmentWhoseLocalTimesDoNotReadIsDropped() {
        let good = S.Assignment(assignmentId: "a", receiverId: "r", userId: "u", caregiverName: "Dana",
                                startsLocal: "2026-11-12T22:00", endsLocal: "2026-11-13T06:00",
                                startsAt: Fixed.now, endsAt: Fixed.now, coverageScheduleId: "rule")
        var bad = good
        bad.endsLocal = "tomorrow"
        XCTAssertEqual(AssignmentInfo(good)?.ends, LocalDateTime(day: LocalDay(year: 2026, month: 11, day: 13),
                                                                 time: "06:00"))
        XCTAssertEqual(AssignmentInfo(good)?.coverageScheduleID, "rule")
        XCTAssertNil(AssignmentInfo(bad))
    }

    func testACoverageScheduleWritesItsDaysInWeekOrderAndItsEndDate() {
        let write = CoverageScheduleWrite(userID: "trevor", days: [.th, .tu], interval: 2, startTime: "22:00",
                                          endTime: "06:00", endsOn: LocalDay(year: 2026, month: 12, day: 1))
        let schema = write.schema
        XCTAssertEqual(schema.rule.byDay, [.tu, .th])
        XCTAssertEqual(schema.rule.interval, 2)
        XCTAssertEqual(schema.rule.freq, .weekly)
        XCTAssertEqual(schema.endsOn, "2026-12-01")
        XCTAssertEqual(schema.startTime, "22:00")
    }

    func testACoverageScheduleReadsItsRule() {
        let c = CoverageScheduleInfo(S.CoverageSchedule(
            coverageScheduleId: "c", receiverId: "r", userId: "u", caregiverName: "Trevor",
            rule: .init(freq: .weekly, interval: 1, byDay: [.tu, .th]), startTime: "08:00", endTime: "16:00",
            startsOn: "2026-11-10", endsOn: nil))
        XCTAssertEqual(c.days, [.tu, .th])
        XCTAssertEqual(c.startsOn, Fixed.nov10)
        XCTAssertNil(c.endsOn)
    }

    func testAnAssignmentWritesItsLocalTimesAsTheAPIReadsThem() {
        let write = AssignmentWrite(userID: "dana", starts: Fixed.local("2026-11-12T22:00"),
                                    ends: Fixed.local("2026-11-13T06:00"))
        XCTAssertEqual(write.schema.startsLocal, "2026-11-12T22:00")
        XCTAssertEqual(write.schema.endsLocal, "2026-11-13T06:00")
    }

    func testLocalTimesReadOnlyTheirOneShape() {
        XCTAssertNotNil(LocalDateTime("2026-11-12T08:00"))
        XCTAssertNil(LocalDateTime("2026-11-12T24:00"))
        XCTAssertNil(LocalDateTime("2026-11-12 08:00"))
        XCTAssertLessThan(Fixed.local("2026-11-12T08:00"), Fixed.local("2026-11-12T09:00"))
        XCTAssertLessThan(Fixed.local("2026-11-12T23:00"), Fixed.local("2026-11-13T01:00"))
    }
}

// MARK: - Words

final class CareReceiverTextTests: XCTestCase {
    func testAnAssignmentNamesItsDayAndHoursEvenOvernight() {
        XCTAssertEqual(TeamText.assignmentLine(Fixed.thursday), "Thu, Nov 12 · 8:00 AM – 4:00 PM")
        let overnight = Fixed.assignment("o", Fixed.dana, "2026-11-12T22:00", "2026-11-13T06:00")
        XCTAssertEqual(TeamText.assignmentLine(overnight), "Thu, Nov 12 · 10:00 PM – 6:00 AM")
        let long = Fixed.assignment("l", Fixed.dana, "2026-11-12T08:00", "2026-11-14T08:00")
        XCTAssertEqual(TeamText.assignmentLine(long), "Thu, Nov 12, 8:00 AM – Sat, Nov 14, 8:00 AM")
    }

    func testACoverageScheduleIsNamedByItsDays() {
        XCTAssertEqual(TeamText.coverageTitle(days: [.tu], interval: 1), "Every Tuesday")
        XCTAssertEqual(TeamText.coverageTitle(days: [.th, .tu], interval: 1), "Every Tuesday and Thursday")
        XCTAssertEqual(TeamText.coverageTitle(days: [.mo, .we, .fr], interval: 1), "Every Mon, Wed, Fri")
        XCTAssertEqual(TeamText.coverageTitle(days: ScheduleWeekday.allCases, interval: 1), "Every day")
        XCTAssertEqual(TeamText.coverageTitle(days: [.tu], interval: 2), "Every 2 weeks on Tuesday")
    }

    func testACoverageScheduleSaysWhenItEndsOrEnded() {
        var rule = Fixed.tuesdayRule
        XCTAssertEqual(TeamText.coverageLine(rule, today: Fixed.nov10), "Trevor · 8:00 AM – 4:00 PM")
        rule = CoverageScheduleInfo(id: "r", receiverID: "e", userID: "t", caregiverName: "Trevor", days: [.tu],
                                    interval: 1, startTime: "08:00", endTime: "16:00", startsOn: nil,
                                    endsOn: LocalDay(year: 2026, month: 11, day: 1))
        XCTAssertEqual(TeamText.coverageLine(rule, today: Fixed.nov10), "Trevor · 8:00 AM – 4:00 PM · ended Nov 1")
    }

    func testOnDutySaysUntilWhenInTheReceiversDay() {
        let now = Fixed.local("2026-11-10T14:00")
        XCTAssertEqual(TeamText.until(Fixed.local("2026-11-10T16:00"), now: now), "until 4:00 PM")
        XCTAssertEqual(TeamText.until(Fixed.local("2026-11-11T08:00"), now: now), "until 8:00 AM tomorrow")
        XCTAssertEqual(TeamText.until(Fixed.local("2026-11-13T08:00"), now: now), "until Fri, Nov 13, 8:00 AM")
    }

    func testAContactWithNoRelationshipShowsItsNumberAlone() {
        XCTAssertEqual(TeamText.contactLine(Fixed.dana555), "Daughter · (555) 014-2277")
        let bare = EmergencyContactInfo(id: "x", name: "Neighbor", relationship: " ", phone: "555-0100")
        XCTAssertEqual(TeamText.contactLine(bare), "555-0100")
    }

    func testACallDialsTheNumbersDigits() {
        XCTAssertEqual(CareReceiverV1View.dial("(555) 014-2277")?.absoluteString, "tel:5550142277")
        XCTAssertEqual(CareReceiverV1View.dial("+44 20 7946 0958")?.absoluteString, "tel:+442079460958")
        XCTAssertNil(CareReceiverV1View.dial("ask Dana"))
    }
}

// MARK: - Care receiver

@MainActor
final class CareReceiverModelTests: XCTestCase {
    func testItLoadsTheDetailAndTheRosterAndAnAdminReadsWhoCanBeAssigned() async {
        let model = CareReceiverModel(receiver: Fixed.admin, service: Fixed.service(onDuty: [Fixed.thursday]),
                                      clock: { Fixed.now })
        await model.load()
        XCTAssertEqual(model.detail.value?.teamName, "The Riverside Group")
        XCTAssertEqual(model.onDuty.value?.count, 1)
        XCTAssertEqual(model.assignments.value, [Fixed.thursday])
        XCTAssertEqual(model.coverage.value, [Fixed.tuesdayRule])
        XCTAssertEqual(model.members.value, Fixed.members)
        XCTAssertTrue(model.canWrite)
        XCTAssertFalse(model.keepsNoRoster)
        XCTAssertEqual(model.rule(for: Fixed.thursday), nil, "Dana's rule isn't listed here")
    }

    func testACaregiverReadsEverythingAndWritesNothing() async {
        let team = Box<String>()
        var service = Fixed.service()
        service.team = { id in team.add(id); throw Down() }
        let model = CareReceiverModel(receiver: Fixed.caregiver, service: service, clock: { Fixed.now })
        await model.load()
        XCTAssertNotNil(model.detail.value)
        XCTAssertFalse(model.canWrite)
        XCTAssertTrue(team.all.isEmpty, "only an admin opens the sheets that need the roster")
    }

    func testAnArchivedReceiverIsReadOnlyEvenForAnAdmin() async {
        let model = CareReceiverModel(receiver: Fixed.admin, service: Fixed.service(detail: Fixed.detail(archived: true)),
                                      clock: { Fixed.now })
        await model.load()
        XCTAssertTrue(model.isArchived)
        XCTAssertFalse(model.canWrite)
    }

    func testATeamWithNoAssignmentsAndNoRulesKeepsNoRoster() async {
        let model = CareReceiverModel(receiver: Fixed.admin, service: Fixed.service(assignments: [], coverage: []),
                                      clock: { Fixed.now })
        await model.load()
        XCTAssertTrue(model.keepsNoRoster)
    }

    func testOneRosterPartFailingLeavesTheRestOnScreen() async {
        var service = Fixed.service()
        service.coverageSchedules = { _ in throw Down() }
        let model = CareReceiverModel(receiver: Fixed.admin, service: service, clock: { Fixed.now })
        await model.load()
        XCTAssertNotNil(model.detail.value)
        XCTAssertEqual(model.coverage, .failed)
        XCTAssertEqual(model.assignments.value, [Fixed.thursday])
        XCTAssertFalse(model.keepsNoRoster, "a failed part says nothing about the roster")
    }

    func testTheDetailFailingFailsTheScreen() async {
        var service = Fixed.service()
        service.careReceiver = { _ in throw Down() }
        let model = CareReceiverModel(receiver: Fixed.admin, service: service, clock: { Fixed.now })
        await model.load()
        XCTAssertEqual(model.detail, .failed)
    }

    func testRestoreStaysAndReadsThemAgain() async {
        let restored = Box<String>()
        var service = Fixed.service()
        service.careReceiver = { _ in Fixed.detail(archived: restored.all.isEmpty) }
        service.restoreReceiver = { id in restored.add(id) }
        let model = CareReceiverModel(receiver: Fixed.admin, service: service, clock: { Fixed.now })
        await model.load()
        XCTAssertTrue(model.isArchived)
        let ok = await model.restore()
        XCTAssertTrue(ok)
        XCTAssertEqual(restored.all, ["eleanor"])
        XCTAssertFalse(model.isArchived)
        XCTAssertTrue(model.canWrite)
    }

    func testARestoreThatFailsSaysSo() async {
        var service = Fixed.service(detail: Fixed.detail(archived: true))
        service.restoreReceiver = { _ in throw AppError.transport }
        let model = CareReceiverModel(receiver: Fixed.admin, service: service, clock: { Fixed.now })
        await model.load()
        let ok = await model.restore()
        XCTAssertFalse(ok)
        XCTAssertEqual(model.restoreError, AppError.transport.message)
    }

    func testArchiveCallsTheServerOnce() async {
        let archived = Box<String>()
        var service = TeamService()
        service.archiveReceiver = { archived.add($0) }
        let model = ArchiveReceiverModel(receiverID: "eleanor", name: "Eleanor", service: service)
        let ok = await model.archive()
        XCTAssertTrue(ok)
        XCTAssertEqual(archived.all, ["eleanor"])
    }
}

// MARK: - The sheets

@MainActor
final class CareReceiverSheetTests: XCTestCase {
    func testEditCareReceiverSendsTheTrimmedNameAndZone() async {
        let sent = Box<(String, String)>()
        var service = TeamService()
        service.changeReceiver = { id, name, zone in
            sent.add((name, zone.identifier))
            return .done(TeamReceiver(id: id, name: name, timeZone: zone))
        }
        let model = EditCareReceiverModel(info: Fixed.detail(), service: service)
        model.name = "  Eleanor R.  "
        model.zone = TimeZone(identifier: "America/Denver")!
        let saved = await model.save()
        XCTAssertEqual(saved?.name, "Eleanor R.")
        XCTAssertEqual(sent.all.first?.0, "Eleanor R.")
        XCTAssertEqual(sent.all.first?.1, "America/Denver")
    }

    func testAWriteToAnArchivedReceiverIsRefusedWithTheReason() async {
        var service = TeamService()
        service.changeReceiver = { _, _, _ in .refused }
        let model = EditCareReceiverModel(info: Fixed.detail(), service: service)
        let saved = await model.save()
        XCTAssertNil(saved)
        XCTAssertEqual(model.error, TeamText.archivedRefusal("Eleanor"))
    }

    func testEditCareInstructionsTrimsAndAnEmptyBodyClearsThem() async {
        let sent = Box<String>()
        var service = TeamService()
        service.changeInstructions = { _, body in sent.add(body); return .done(Fixed.detail()) }
        let model = EditInstructionsModel(
            info: Fixed.detail(instructions: CareInstructionsInfo(body: "Old", updatedByName: "Trevor",
                                                                   updatedAt: Fixed.now)),
            service: service)
        XCTAssertEqual(model.body, "Old")
        XCTAssertEqual(model.stamp?.updatedByName, "Trevor")
        model.body = "\n  \n"
        _ = await model.save()
        XCTAssertEqual(sent.all, [""])
    }

    func testEditCareInstructionsRefusesMoreThanTheAPIKeeps() {
        let model = EditInstructionsModel(info: Fixed.detail(), service: TeamService())
        model.body = String(repeating: "a", count: EditInstructionsModel.maxLength + 1)
        XCTAssertFalse(model.canSave)
    }

    func testContactsKeepTheirIDsAndOrderAndABlankNewOneIsDropped() async {
        let sent = Box<[EmergencyContactWrite]>()
        var service = TeamService()
        service.changeContacts = { _, list in sent.add(list); return .done(Fixed.detail()) }
        let model = EmergencyContactsModel(info: Fixed.detail(contacts: [Fixed.dana555, Fixed.ahn]), service: service)
        model.add()
        model.add()
        model.drafts[3].name = " Marcus "
        model.drafts[3].phone = "555-0101"
        // Marcus to the top, Dr. Ahn removed.
        model.move(model.drafts[3].id, to: model.drafts[0].id)
        model.remove(model.drafts[2].id)
        XCTAssertTrue(model.problems.isEmpty)
        _ = await model.save()
        XCTAssertEqual(sent.all.first, [
            EmergencyContactWrite(contactID: nil, name: "Marcus", relationship: "", phone: "555-0101"),
            EmergencyContactWrite(contactID: "c-dana", name: "Dana", relationship: "Daughter", phone: "(555) 014-2277"),
        ])
    }

    func testAContactNeedsANameAndANumber() {
        let model = EmergencyContactsModel(info: Fixed.detail(), service: TeamService())
        model.add()
        model.drafts[0].relationship = "Neighbor"
        XCTAssertEqual(model.problems, ["Give every contact a name.", "Give every contact a phone number."])
        XCTAssertFalse(model.canSave)
    }

    func testContactsMoveOnePlaceForVoiceOverAndStopAtTheEnds() {
        let model = EmergencyContactsModel(info: Fixed.detail(contacts: [Fixed.dana555, Fixed.ahn]),
                                           service: TeamService())
        let first = model.drafts[0].id
        model.move(first, by: -1)
        XCTAssertEqual(model.drafts.first?.id, first)
        model.move(first, by: 1)
        XCTAssertEqual(model.drafts.last?.id, first)
    }

    func testContactsStopAtTwenty() {
        let model = EmergencyContactsModel(info: Fixed.detail(), service: TeamService())
        for _ in 0..<25 { model.add() }
        XCTAssertEqual(model.drafts.count, EmergencyContactsModel.maxContacts)
    }
}

// MARK: - An assignment

@MainActor
final class AssignmentModelTests: XCTestCase {
    private func model(_ existing: AssignmentInfo? = nil, service: TeamService = TeamService(),
                       now: Date = Fixed.now) -> AssignmentModel {
        AssignmentModel(receiverID: "eleanor", receiverName: "Eleanor", zone: Fixed.chicago, existing: existing,
                        members: Fixed.members, service: service, clock: { now })
    }

    func testANewOneStartsTodayEightToFourWithNobodyChosen() {
        let m = model()
        XCTAssertEqual(m.day, Fixed.nov10)
        XCTAssertEqual(m.starts, Fixed.local("2026-11-10T08:00"))
        XCTAssertEqual(m.ends, Fixed.local("2026-11-10T16:00"))
        XCTAssertTrue(m.problems.contains("Choose a caregiver."))
    }

    func testAnEndEarlierThanTheStartRunsOvernight() {
        let m = model()
        m.userID = "dana"
        m.setStart("22:00")
        m.setEnd("06:00")
        XCTAssertEqual(m.ends, Fixed.local("2026-11-11T06:00"))
        XCTAssertTrue(m.problems.isEmpty)
    }

    func testTheSameStartAndEndIsRefused() {
        let m = model()
        m.userID = "dana"
        m.setEnd("08:00")
        XCTAssertTrue(m.problems.contains("The end time can’t be the same as the start."))
    }

    func testOneAlreadyOverCannotBeMade() {
        let m = model()
        m.userID = "dana"
        m.setStart("09:00")
        m.setEnd("10:00")
        XCTAssertTrue(m.problems.contains("That time has already passed."), "it is 2:00 PM in Chicago")
    }

    func testAnExistingOneKeepsItsDaysUntilTheHoursChange() {
        let long = Fixed.assignment("l", Fixed.dana, "2026-11-12T08:00", "2026-11-14T08:00")
        let m = model(long)
        XCTAssertEqual(m.ends, Fixed.local("2026-11-14T08:00"))
        m.setEnd("09:00")
        XCTAssertEqual(m.ends, Fixed.local("2026-11-12T09:00"))
    }

    func testSavingSomeoneElseHandsItToThemAndChangesThatOneOnly() async {
        let sent = Box<(String, AssignmentWrite)>()
        var service = TeamService()
        service.changeAssignment = { id, write in sent.add((id, write)); return .done(Fixed.thursday) }
        let m = model(Fixed.thursday, service: service)
        m.userID = "marcus"
        XCTAssertTrue(m.isHandOff)
        let ok = await m.save()
        XCTAssertTrue(ok)
        XCTAssertEqual(sent.all.first?.0, "thu")
        XCTAssertEqual(sent.all.first?.1, AssignmentWrite(userID: "marcus", starts: Fixed.local("2026-11-12T08:00"),
                                                          ends: Fixed.local("2026-11-12T16:00")))
    }

    func testANewOneIsAdded() async {
        let added = Box<String>()
        var service = TeamService()
        service.addAssignment = { receiverID, _ in added.add(receiverID); return .done(Fixed.thursday) }
        let m = model(service: service)
        m.userID = "dana"
        m.day = LocalDay(year: 2026, month: 11, day: 12)
        let ok = await m.save()
        XCTAssertTrue(ok)
        XCTAssertEqual(added.all, ["eleanor"])
    }

    func testAnEndedOrArchivedOneIsRefusedWithBothReasons() async {
        var service = TeamService()
        service.changeAssignment = { _, _ in .refused }
        service.removeAssignment = { _ in .refused }
        let m = model(Fixed.thursday, service: service)
        let saved = await m.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(m.error, TeamText.assignmentRefused)
        let removed = await m.remove()
        XCTAssertFalse(removed)
        XCTAssertEqual(m.error, TeamText.assignmentRefused)
    }

    func testANewOneOnAnArchivedReceiverSaysSo() async {
        var service = TeamService()
        service.addAssignment = { _, _ in .refused }
        let m = model(service: service)
        m.userID = "dana"
        _ = await m.save()
        XCTAssertEqual(m.error, TeamText.archivedRefusal("Eleanor"))
    }

    func testRemoveDropsThisOne() async {
        let removed = Box<String>()
        var service = TeamService()
        service.removeAssignment = { id in removed.add(id); return .done(Done()) }
        let m = model(Fixed.thursday, service: service)
        let ok = await m.remove()
        XCTAssertTrue(ok)
        XCTAssertEqual(removed.all, ["thu"])
    }

    func testAFormerCaregiversAssignmentNamesThemButMustBeHandedOn() {
        let former = AssignmentInfo(id: "f", receiverID: "eleanor", userID: "gone", caregiverName: "a former caregiver",
                                    starts: Fixed.local("2026-11-12T08:00"), ends: Fixed.local("2026-11-12T16:00"),
                                    startsAt: Fixed.now, endsAt: Fixed.now, coverageScheduleID: nil)
        let m = model(former)
        XCTAssertEqual(m.caregiverName, "a former caregiver")
        XCTAssertTrue(m.problems.contains("Choose someone on this care team now."))
    }
}

// MARK: - A coverage schedule

@MainActor
final class CoverageScheduleModelTests: XCTestCase {
    private func model(_ existing: CoverageScheduleInfo? = nil, service: TeamService = TeamService())
        -> CoverageScheduleModel {
        CoverageScheduleModel(receiverID: "eleanor", receiverName: "Eleanor", zone: Fixed.chicago, existing: existing,
                              members: Fixed.members, service: service, clock: { Fixed.now })
    }

    func testANewOneNeedsACaregiverAndADay() {
        let m = model()
        XCTAssertEqual(m.problems, ["Choose a caregiver.", "Choose at least one day."])
        m.userID = "trevor"
        m.toggle(.tu)
        XCTAssertTrue(m.problems.isEmpty)
        XCTAssertEqual(m.write, CoverageScheduleWrite(userID: "trevor", days: [.tu], interval: 1, startTime: "08:00",
                                                      endTime: "16:00", endsOn: nil))
    }

    func testTheSameStartAndEndIsRefusedButOvernightIsNot() {
        let m = model(Fixed.tuesdayRule)
        m.endTime = "08:00"
        XCTAssertEqual(m.problems, ["The end time can’t be the same as the start."])
        m.startTime = "22:00"
        m.endTime = "06:00"
        XCTAssertTrue(m.problems.isEmpty)
    }

    func testAnEndDateBeforeTodayIsRefusedUnlessItWasAlreadySaved() {
        let m = model(Fixed.tuesdayRule)
        m.endsOn = LocalDay(year: 2026, month: 11, day: 9)
        XCTAssertEqual(m.problems, ["The end date can’t be before today."])
        m.endsOn = Fixed.nov10
        XCTAssertTrue(m.problems.isEmpty, "ending it today is how a rotation stops now")
    }

    func testAnExistingRulesIntervalIsKept() {
        let every2 = CoverageScheduleInfo(id: "r", receiverID: "eleanor", userID: "trevor", caregiverName: "Trevor",
                                          days: [.tu], interval: 2, startTime: "08:00", endTime: "16:00",
                                          startsOn: nil, endsOn: nil)
        XCTAssertEqual(model(every2).write?.interval, 2)
    }

    func testSavingAnExistingOneChangesIt() async {
        let changed = Box<String>()
        var service = TeamService()
        service.changeCoverage = { id, _ in changed.add(id); return .done(Fixed.tuesdayRule) }
        let m = model(Fixed.tuesdayRule, service: service)
        m.toggle(.th)
        let ok = await m.save()
        XCTAssertTrue(ok)
        XCTAssertEqual(changed.all, ["rule-trevor"])
    }

    func testRemoveIsRefusedForAnArchivedReceiver() async {
        var service = TeamService()
        service.removeCoverage = { _ in .refused }
        let m = model(Fixed.tuesdayRule, service: service)
        let ok = await m.remove()
        XCTAssertFalse(ok)
        XCTAssertEqual(m.removeError, TeamText.archivedRefusal("Eleanor"))
    }

    func testAServer400IsShownAsItsMessage() async {
        var service = TeamService()
        service.addCoverage = { _, _ in .rejected("start_time must differ from end_time") }
        let m = model(service: service)
        m.userID = "trevor"
        m.toggle(.tu)
        _ = await m.save()
        XCTAssertEqual(m.error, "start_time must differ from end_time")
    }
}

// MARK: - Home's header

@MainActor
final class HomeOnDutyTests: XCTestCase {
    private func model(onDuty: @escaping @Sendable (String) async throws -> [AssignmentInfo]) -> HomeModel {
        var home = HomeService(
            needsAttention: { _, _ in [] },
            comingUp: { _, _ in [] },
            dayTimeline: { _, day in DayTimeline(day: day, items: []) },
            entry: { _ in throw Down() },
            journalNote: { _ in throw Down() }
        )
        home.onDuty = onDuty
        var trackers = TrackersFixtures.service()
        trackers.listTrackers = { _ in [] }
        return HomeModel(home: home, trackers: trackers, clock: { Fixed.now })
    }

    func testHomeNamesEveryoneOnDutyForTheReceiverItShows() async {
        let asked = Box<String>()
        let both = [Fixed.thursday, Fixed.assignment("aide", Fixed.marcus, "2026-11-10T08:00", "2026-11-10T20:00")]
        let model = model { id in asked.add(id); return both }
        await model.show(Fixed.admin)
        XCTAssertEqual(model.onDuty, both, "assignments can overlap")
        XCTAssertEqual(asked.all, ["eleanor"])
    }

    func testATeamWithNoRosterSeesNothingThere() async {
        let model = model { _ in [] }
        await model.show(Fixed.admin)
        XCTAssertTrue(model.onDuty.isEmpty)
        XCTAssertEqual(model.phase, .loaded)
    }

    func testWhoIsOnDutyFailingDoesNotFailHome() async {
        let model = model { _ in throw Down() }
        await model.show(Fixed.admin)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.onDuty.isEmpty)
    }
}
