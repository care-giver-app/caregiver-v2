import XCTest
import CaregiverAPI
@testable import Caregiver

private typealias S = Components.Schemas

/// Fixed teams, people and zones: nothing here reads the device zone or the network.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!
    static let denver = TimeZone(identifier: "America/Denver")!

    static let riverside = Account.Team(teamID: "riverside", name: "The Riverside Group", role: "admin")
    static let johnson = Account.Team(teamID: "johnson", name: "Johnson Family", role: "caregiver")
    static let delgado = Account.Team(teamID: "delgado", name: "Delgado Family", role: "caregiver")

    static let trevor = Account(name: "Trevor", email: "t@example.com", teams: [riverside, johnson], userID: "trevor")
    static let trevorPlusDelgado = Account(name: "Trevor", email: "t@example.com",
                                           teams: [riverside, johnson, delgado], userID: "trevor")

    static let eleanor = TeamReceiver(id: "eleanor", name: "Eleanor", timeZone: chicago)
    static let walter = TeamReceiver(id: "walter", name: "Walter", timeZone: denver)

    static let invitation = PendingInvitation(code: "delgado-code", teamName: "Delgado Family", invitedByName: "Lucia")

    static let me = TeamMemberInfo(userID: "trevor", name: "Trevor", role: .admin)
    static let dana = TeamMemberInfo(userID: "dana", name: "Dana", role: .admin)
    static let marcus = TeamMemberInfo(userID: "marcus", name: "Marcus", role: .caregiver)

    static func detail(_ members: [TeamMemberInfo], myRole: TeamRole = .admin) -> TeamDetailInfo {
        TeamDetailInfo(teamID: riverside.teamID, name: riverside.name, myRole: myRole, members: members)
    }

    static let pending = TeamInvitationInfo(code: "OLD", email: "jordan@email.com", invitedByName: "Trevor",
                                            createdAt: Date(timeIntervalSince1970: 0),
                                            expiresAt: Date(timeIntervalSince1970: 14 * 86_400))

    /// Riverside has Eleanor, Johnson has Walter; the Delgado invitation waits.
    static func service(account: Account = trevor) -> TeamService {
        var s = TeamService()
        s.account = { account }
        s.listInvitationsForMe = { [invitation] }
        s.listReceivers = { teamID, archived in
            if archived { return [] }
            switch teamID {
            case riverside.teamID: return [eleanor]
            case johnson.teamID: return [walter]
            default: return []
            }
        }
        return s
    }
}

private struct Down: Error {}

/// Counts calls made from the services' closures.
private final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

// MARK: - Mapping

final class TeamServiceMappingTests: XCTestCase {
    func testTheAccountCarriesTheCaregiversIDForTheirOwnRow() {
        let account = Account(S.MyAccount(
            caregiver: .init(userId: "sub-1", email: "t@example.com", name: "Trevor"),
            teams: [.init(teamId: "riverside", name: "The Riverside Group", role: .admin)]))
        XCTAssertEqual(account.userID, "sub-1")
        XCTAssertEqual(account.teams, [Account.Team(teamID: "riverside", name: "The Riverside Group", role: "admin")])
    }

    func testATeamKeepsItsRosterInTheServersOrder() {
        let detail = TeamDetailInfo(S.TeamDetail(teamId: "t", name: "The Riverside Group", myRole: .caregiver, members: [
            .init(userId: "dana", name: "Dana", role: .admin),
            .init(userId: "trevor", name: "Trevor", role: .caregiver),
        ]))
        XCTAssertEqual(detail.myRole, .caregiver)
        XCTAssertEqual(detail.members, [TeamMemberInfo(userID: "dana", name: "Dana", role: .admin),
                                        TeamMemberInfo(userID: "trevor", name: "Trevor", role: .caregiver)])
    }

    func testNotificationChoicesRoundTrip() {
        let choices = TeamNotificationChoices(reminders: false, rangeAlerts: true, gapAlerts: false,
                                              unrecordedAlerts: true)
        XCTAssertEqual(TeamNotificationChoices(choices.schema), choices)
    }

    func testZonesReadAsTheirGenericNames() {
        XCTAssertEqual(TeamText.zoneName(Fixed.chicago), "Central time")
        XCTAssertEqual(TeamText.zoneName(Fixed.denver), "Mountain time")
        XCTAssertEqual(AddCareReceiverModel.label(TimeZone(identifier: "America/Phoenix")!), "Mountain time (Arizona)")
    }

    func testAnInvitationSaysHowLongItHasLeft() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TeamText.expires(now.addingTimeInterval(7 * 86_400 + 60), now: now), "Expires in 7 days")
        XCTAssertEqual(TeamText.expires(now.addingTimeInterval(86_400 + 60), now: now), "Expires tomorrow")
        XCTAssertEqual(TeamText.expires(now.addingTimeInterval(3600), now: now), "Expires today")
    }
}

// MARK: - Team

@MainActor
final class TeamListModelTests: XCTestCase {
    func testEachTeamShowsItsReceiversAsTheCaregiverSeesThem() async {
        let model = TeamListModel(account: Fixed.trevor, service: Fixed.service())
        await model.load()

        XCTAssertEqual(model.teams.map(\.id), ["riverside", "johnson"])
        XCTAssertEqual(model.teams[0].receivers, .loaded([Fixed.eleanor.managed(by: Fixed.riverside)]))
        XCTAssertEqual(model.teams[0].receivers.value?.first?.canManage, true, "Trevor is Riverside's admin")
        XCTAssertEqual(model.teams[1].receivers.value?.first?.canManage, false, "and Johnson's caregiver")
        XCTAssertEqual(model.invitations, .loaded([Fixed.invitation]))
    }

    func testOneTeamFailingLeavesTheOthersOnScreen() async {
        var service = Fixed.service()
        service.listReceivers = { teamID, _ in
            if teamID == Fixed.johnson.teamID { throw Down() }
            return [Fixed.eleanor]
        }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        await model.load()

        XCTAssertNotNil(model.teams[0].receivers.value)
        XCTAssertEqual(model.teams[1].receivers, .failed)
    }

    func testInvitationsThatCouldNotBeReadAreNeverAnEmptyList() async {
        var service = Fixed.service()
        service.listInvitationsForMe = { throw Down() }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        await model.load()
        XCTAssertEqual(model.invitations, .failed)
    }

    func testAcceptingMakesTheTeamARowOnTheList() async {
        var service = Fixed.service(account: Fixed.trevorPlusDelgado)
        service.redeem = { _ in .joined }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        await model.load()
        await model.accept(Fixed.invitation)

        XCTAssertEqual(model.account, Fixed.trevorPlusDelgado)
        XCTAssertEqual(model.teams.map(\.id), ["riverside", "johnson", "delgado"])
        XCTAssertNil(model.invitationError)
    }

    func testAcceptingATeamYouAreOnIsRefusedAsAlreadyAMember() async {
        var service = Fixed.service()
        service.redeem = { _ in .alreadyMember }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        await model.accept(Fixed.invitation)

        XCTAssertEqual(model.invitationError, TeamText.alreadyMember)
        XCTAssertEqual(model.account, Fixed.trevor)
    }

    func testAStaleInvitationSaysSoAndTheListIsReadAgain() async {
        let reads = Count()
        var service = Fixed.service()
        service.redeem = { _ in .noLongerValid }
        service.listInvitationsForMe = { reads.hit(); return [] }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        await model.accept(Fixed.invitation)

        XCTAssertEqual(model.invitationError, TeamText.invitationNoLongerValid)
        XCTAssertEqual(reads.value, 1)
        XCTAssertEqual(model.invitations, .loaded([]))
    }

    func testNothingPastedIsNoCall() async {
        let calls = Count()
        var service = Fixed.service()
        service.redeem = { _ in calls.hit(); return .joined }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        model.code = "   "
        await model.joinWithCode()
        XCTAssertEqual(calls.value, 0)
        XCTAssertNil(model.codeError)
    }

    func testAnInvalidCodeSaysOnlyThatItIsNoLongerValid() async {
        var service = Fixed.service()
        service.redeem = { _ in .noLongerValid }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        model.startPasting()
        model.code = "7K2P-9QX4-M3LT"
        await model.joinWithCode()

        XCTAssertEqual(model.codeError, TeamText.codeNoLongerValid)
        XCTAssertTrue(model.isPasting, "it stays on Team with the code still there")
        XCTAssertEqual(model.code, "7K2P-9QX4-M3LT")
    }

    func testAPastedCodeJoinsAndClosesTheField() async {
        var service = Fixed.service(account: Fixed.trevorPlusDelgado)
        service.redeem = { code in
            XCTAssertEqual(code, "ABC", "trimmed")
            return .joined
        }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        model.startPasting()
        model.code = " ABC \n"
        await model.joinWithCode()

        XCTAssertFalse(model.isPasting)
        XCTAssertEqual(model.code, "")
        XCTAssertEqual(model.account.teams.last, Fixed.delgado)
    }

    func testACreatedTeamIsARowEvenWhenTheTeamsCannotBeReadAgain() async {
        var service = Fixed.service()
        service.account = { throw Down() }
        let model = TeamListModel(account: Fixed.trevor, service: service)
        let created = Account.Team(teamID: "new", name: "Delgado Family", role: "admin")
        await model.created(created)

        XCTAssertEqual(model.account.teams.last, created)
        XCTAssertEqual(model.teams.last?.receivers, .loaded([]))
        XCTAssertTrue(model.accountFailed)
    }

    func testLeavingTheLastTeamLeavesTeamEmptyRatherThanGone() async {
        let alone = Account(name: "Trevor", email: "t@example.com", teams: [], userID: "trevor")
        let model = TeamListModel(account: Fixed.trevor, service: Fixed.service(account: alone))
        await model.refreshAccount()

        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.teams, [])
        XCTAssertEqual(model.invitations, .loaded([Fixed.invitation]), "the ways in are still offered")
    }
}

// MARK: - Care team

@MainActor
final class CareTeamModelTests: XCTestCase {
    private func model(_ detail: TeamDetailInfo, team: Account.Team = Fixed.riverside,
                       invitations: @escaping @Sendable (String) async throws -> [TeamInvitationInfo] = { _ in [] })
        -> CareTeamModel {
        var service = TeamService()
        service.team = { _ in detail }
        service.listInvitations = invitations
        service.listReceivers = { _, archived in archived ? [Fixed.walter] : [] }
        return CareTeamModel(team: team, myUserID: "trevor", service: service)
    }

    func testAdminsSeePendingInvitationsAndArchivedReceivers() async {
        let m = model(Fixed.detail([Fixed.me, Fixed.dana, Fixed.marcus]), invitations: { _ in [Fixed.pending] })
        await m.load()
        XCTAssertEqual(m.invitations, .loaded([Fixed.pending]))
        XCTAssertEqual(m.archived.value?.map(\.id), ["walter"])
    }

    func testACaregiverNeverAsksForInvitations() async {
        let asked = Count()
        let m = model(Fixed.detail([Fixed.dana, Fixed.me], myRole: .caregiver), team: Fixed.johnson,
                      invitations: { _ in asked.hit(); return [] })
        await m.load()
        XCTAssertEqual(asked.value, 0)
        XCTAssertFalse(m.isAdmin)
    }

    func testACaregiverOpensOnlyTheirOwnRow() async {
        let caregiverMe = TeamMemberInfo(userID: "trevor", name: "Trevor", role: .caregiver)
        let m = model(Fixed.detail([Fixed.dana, caregiverMe], myRole: .caregiver))
        await m.load()
        XCTAssertTrue(m.opens(caregiverMe))
        XCTAssertFalse(m.opens(Fixed.dana))
    }

    func testTheOnlyAdminIsRefusedLeavingWithTheReason() async {
        let m = model(Fixed.detail([Fixed.me, Fixed.marcus]))
        await m.load()
        XCTAssertTrue(m.isOnlyAdmin)
        XCTAssertFalse(m.tryLeave())
        XCTAssertTrue(m.leaveRefused)
    }

    func testAnAdminWithAnotherAdminMayLeave() async {
        let m = model(Fixed.detail([Fixed.me, Fixed.dana]))
        await m.load()
        XCTAssertTrue(m.tryLeave())
        XCTAssertFalse(m.leaveRefused)
        XCTAssertFalse(m.isLastCaregiver)
    }

    func testYourOwnRowAsTheLastCaregiverOffersClosingNotTheOnlyAdminRefusal() async {
        let m = model(Fixed.detail([Fixed.me]))
        await m.load()
        XCTAssertEqual(m.exitKind(), .close)
        XCTAssertFalse(m.leaveRefused)
    }

    func testTheOnlyAdminWithOthersIsRefusedAnExit() async {
        let m = model(Fixed.detail([Fixed.me, Fixed.marcus]))
        await m.load()
        XCTAssertNil(m.exitKind())
        XCTAssertTrue(m.leaveRefused)
    }

    func testTheLastCaregiverClosesRatherThanLeaves() async {
        let m = model(Fixed.detail([Fixed.me]))
        await m.load()
        XCTAssertTrue(m.isLastCaregiver)
    }

    func testANewInvitationLeadsThePendingList() async {
        let m = model(Fixed.detail([Fixed.me, Fixed.dana]), invitations: { _ in [Fixed.pending] })
        await m.load()
        let new = TeamInvitationInfo(code: "NEW", email: "sam@email.com", invitedByName: "Trevor",
                                     createdAt: Date(timeIntervalSince1970: 1), expiresAt: Date(timeIntervalSince1970: 2))
        m.invitationCreated(new)
        XCTAssertEqual(m.invitations.value?.map(\.code), ["NEW", "OLD"])
    }
}

// MARK: - Sheets

@MainActor
final class TeamSheetModelTests: XCTestCase {
    func testDemotingTheOnlyAdminIsRefusedWithoutAsking() async {
        let calls = Count()
        var service = TeamService()
        service.changeRole = { _, _, _ in calls.hit(); return .done }
        let m = MemberActionsModel(member: Fixed.dana, teamID: "riverside", teamName: "The Riverside Group",
                                   isOnlyAdmin: true, service: service)
        let done = await m.perform(.makeCaregiver)
        XCTAssertFalse(done)
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(m.refusal, TeamText.lastAdmin("Dana"))
    }

    func testTheServerRefusingTheLastAdminSaysWhy() async {
        var service = TeamService()
        service.removeMember = { _, _ in .lastAdmin }
        let m = MemberActionsModel(member: Fixed.dana, teamID: "riverside", teamName: "The Riverside Group",
                                   isOnlyAdmin: false, service: service)
        let done = await m.perform(.remove)
        XCTAssertFalse(done)
        XCTAssertEqual(m.refusal, TeamText.lastAdmin("Dana"))
    }

    func testMakingACaregiverAnAdminGoesBack() async {
        var service = TeamService()
        service.changeRole = { _, userID, role in
            XCTAssertEqual(userID, "marcus")
            XCTAssertEqual(role, .admin)
            return .done
        }
        let m = MemberActionsModel(member: Fixed.marcus, teamID: "riverside", teamName: "The Riverside Group",
                                   isOnlyAdmin: false, service: service)
        XCTAssertEqual(m.roleAction, .makeAdmin)
        let done = await m.perform(.makeAdmin)
        XCTAssertTrue(done)
    }

    func testLeavingRemovesYourOwnMembership() async {
        var service = TeamService()
        service.removeMember = { teamID, userID in
            XCTAssertEqual(teamID, "riverside")
            XCTAssertEqual(userID, "trevor")
            return .done
        }
        let m = LeaveTeamModel(kind: .leave, teamID: "riverside", myUserID: "trevor", service: service)
        let outcome = await m.confirm()
        XCTAssertEqual(outcome, .left)
    }

    func testLeavingAsTheOnlyAdminComesBackRefused() async {
        var service = TeamService()
        service.removeMember = { _, _ in .lastAdmin }
        let m = LeaveTeamModel(kind: .leave, teamID: "riverside", myUserID: "trevor", service: service)
        let outcome = await m.confirm()
        XCTAssertEqual(outcome, .onlyAdmin)
    }

    func testClosingATeamSomeoneJoinedStaysUpSayingSo() async {
        var service = TeamService()
        service.closeTeam = { _ in .notLastCaregiver }
        let m = LeaveTeamModel(kind: .close, teamID: "riverside", myUserID: "trevor", service: service)
        let outcome = await m.confirm()
        XCTAssertNil(outcome)
        XCTAssertEqual(m.failure, TeamText.notLastCaregiver)
    }

    func testInvitingSomeoneAlreadyOnTheTeamIsRefused() async {
        var service = TeamService()
        service.invite = { _, _ in .alreadyMember }
        let m = InviteCaregiverModel(teamID: "riverside", service: service)
        m.email = "dana@email.com"
        let created = await m.create()
        XCTAssertNil(created)
        XCTAssertEqual(m.error, TeamText.inviteeAlreadyMember)
    }

    func testAnInvitationComesBackWithItsCode() async {
        var service = TeamService()
        service.invite = { _, email in
            XCTAssertEqual(email, "jordan@email.com")
            return .created(Fixed.pending)
        }
        let m = InviteCaregiverModel(teamID: "riverside", service: service)
        XCTAssertFalse(m.canCreate)
        m.email = " jordan@email.com "
        let created = await m.create()
        XCTAssertEqual(created, Fixed.pending)
    }

    func testAnAddedReceiverIsManagedByTheAdminWhoAddedThem() async {
        var service = TeamService()
        service.addReceiver = { _, name, zone in .added(TeamReceiver(id: "rosa", name: name, timeZone: zone)) }
        let m = AddCareReceiverModel(team: Fixed.riverside, service: service, zone: Fixed.chicago)
        m.name = "Rosa"
        let added = await m.add()
        XCTAssertEqual(added?.id, "rosa")
        XCTAssertEqual(added?.timeZone, Fixed.chicago)
        XCTAssertEqual(added?.canManage, true)
    }

    func testTheDevicesZoneIsAlwaysOffered() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(AddCareReceiverModel.zones(including: tokyo).first, tokyo)
        XCTAssertEqual(AddCareReceiverModel.zones(including: Fixed.chicago), AddCareReceiverModel.usZones)
    }

    func testANotificationChangeThatDoesNotSaveIsPutBack() async {
        var service = TeamService()
        service.notifications = { _ in .allOn }
        service.changeNotifications = { _, _ in throw Down() }
        let m = TeamNotificationsModel(team: Fixed.riverside, service: service)
        await m.load()
        await m.set(\.gapAlerts, to: false)
        XCTAssertEqual(m.choices, .loaded(.allOn))
        XCTAssertTrue(m.saveFailed)
    }

    func testANotificationChangeSavesTheWholeTeamsChoices() async {
        var service = TeamService()
        service.notifications = { _ in .allOn }
        service.changeNotifications = { _, choices in choices }
        let m = TeamNotificationsModel(team: Fixed.riverside, service: service)
        await m.load()
        await m.set(\.reminders, to: false)
        XCTAssertEqual(m.choices.value?.reminders, false)
        XCTAssertEqual(m.choices.value?.rangeAlerts, true)
        XCTAssertFalse(m.saveFailed)
    }
}

// MARK: - Home following Team

@MainActor
final class ActiveReceiverAdoptTests: XCTestCase {
    private func trackers() -> TrackersService {
        var s = TrackersFixtures.service()
        s.listReceivers = { teamID in teamID == Fixed.delgado.teamID ? [Fixed.walter] : [] }
        return s
    }

    func testJoiningATeamChoosesFromItsReceivers() async {
        let alone = Account(name: "Trevor", email: "t@example.com", teams: [Fixed.riverside], userID: "trevor")
        let model = ActiveReceiverModel(account: alone, service: trackers(), store: .inMemory())
        await model.load()
        guard case .noReceivers = model.phase else { return XCTFail("Riverside has nobody") }

        await model.adopt(Account(name: "Trevor", email: "t@example.com", teams: [Fixed.riverside, Fixed.delgado],
                                  userID: "trevor"))
        XCTAssertEqual(model.active?.receiver.id, "walter")
        XCTAssertEqual(model.active?.team, Fixed.delgado)
    }

    func testLeavingEveryTeamIsNoTeamRatherThanAFailure() async {
        let alone = Account(name: "Trevor", email: "t@example.com", teams: [Fixed.delgado], userID: "trevor")
        let model = ActiveReceiverModel(account: alone, service: trackers(), store: .inMemory())
        await model.load()
        await model.adopt(Account(name: "Trevor", email: "t@example.com", teams: [], userID: "trevor"))
        XCTAssertEqual(model.phase, .noTeam)
    }
}
