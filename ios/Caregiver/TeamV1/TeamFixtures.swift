#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Trevor, admin of The Riverside Group (Trevor,
/// Dana and Marcus; Eleanor, Harold and an archived Rosa; jordan@email.com invited) and a
/// caregiver on Johnson Family (Ana Johnson, Ben Johnson, Dana; Walter), with Lucia's
/// Delgado Family invitation waiting.
enum TeamFixtures {
    static let riverside = HomeFixtures.riverside
    static let johnson = HomeFixtures.johnson

    static let trevor = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [riverside, johnson],
                                userID: "user-trevor")
    static let trevorNoTeam = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [],
                                      userID: "user-trevor")

    static let trevorMember = TeamMemberInfo(userID: "user-trevor", name: "Trevor", role: .admin)
    static let dana = TeamMemberInfo(userID: "user-dana", name: "Dana", role: .admin)
    static let marcus = TeamMemberInfo(userID: "user-marcus", name: "Marcus", role: .caregiver)

    static let riversideDetail = TeamDetailInfo(teamID: riverside.teamID, name: riverside.name, myRole: .admin,
                                                members: [trevorMember, dana, marcus])
    /// The `Needs an admin` exception in fixtures.md: Dana a caregiver, Trevor the last admin.
    static let riversideOnlyAdmin = TeamDetailInfo(
        teamID: riverside.teamID, name: riverside.name, myRole: .admin,
        members: [trevorMember, TeamMemberInfo(userID: "user-dana", name: "Dana", role: .caregiver), marcus])
    static let johnsonDetail = TeamDetailInfo(
        teamID: johnson.teamID, name: johnson.name, myRole: .caregiver,
        members: [TeamMemberInfo(userID: "user-ana", name: "Ana Johnson", role: .admin),
                  TeamMemberInfo(userID: "user-ben", name: "Ben Johnson", role: .caregiver),
                  TeamMemberInfo(userID: "user-dana", name: "Dana", role: .caregiver),
                  TeamMemberInfo(userID: "user-trevor", name: "Trevor", role: .caregiver)])

    static var jordanInvitation: TeamInvitationInfo {
        TeamInvitationInfo(code: "7K2P-9QX4-M3LT", email: "jordan@email.com", invitedByName: "Trevor",
                           createdAt: Date().addingTimeInterval(-7 * 86_400),
                           expiresAt: Date().addingTimeInterval(7 * 86_400 + 3600))
    }

    static let receiversByTeam: [String: [TeamReceiver]] = [
        riverside.teamID: [HomeFixtures.eleanor, HomeFixtures.harold],
        johnson.teamID: [HomeFixtures.walter],
    ]
    static let archivedByTeam: [String: [TeamReceiver]] = [riverside.teamID: [HomeFixtures.rosa]]

    // MARK: Care receiver — Eleanor's instructions, contacts and coverage (fixtures.md)

    static let eleanorInstructions = CareInstructionsInfo(
        body: "Morning pills go down with food — she will skip them otherwise. The walker comes along for "
            + "anything past the kitchen, including the hallway. Hearing aid goes in before anyone tries to "
            + "talk to her, or she will nod at things she has not heard.",
        updatedByName: "Trevor",
        updatedAt: Date().addingTimeInterval(-60 * 86_400))

    static let eleanorDetail = CareReceiverInfo(
        id: HomeFixtures.eleanor.id, teamID: riverside.teamID, teamName: riverside.name, name: "Eleanor",
        timeZone: HomeFixtures.chicago, isArchived: false, archivedByName: nil, archivedAt: nil,
        instructions: eleanorInstructions,
        contacts: [EmergencyContactInfo(id: "contact-dana", name: "Dana", relationship: "Daughter",
                                        phone: "(555) 014-2277"),
                   EmergencyContactInfo(id: "contact-ahn", name: "Dr. Ahn", relationship: "Primary care",
                                        phone: "(555) 019-9040")])

    /// Nothing written, nobody to call, no roster: Figma 451:3553's empty parts.
    static let haroldDetail = CareReceiverInfo(
        id: HomeFixtures.harold.id, teamID: riverside.teamID, teamName: riverside.name, name: "Harold",
        timeZone: HomeFixtures.chicago, isArchived: false, archivedByName: nil, archivedAt: nil,
        instructions: nil, contacts: [])

    static let rosaDetail = CareReceiverInfo(
        id: HomeFixtures.rosa.id, teamID: riverside.teamID, teamName: riverside.name, name: "Rosa",
        timeZone: HomeFixtures.chicago, isArchived: true, archivedByName: "Dana",
        archivedAt: Date().addingTimeInterval(-20 * 86_400),
        instructions: CareInstructionsInfo(body: "Lights stay on in the hallway at night.", updatedByName: "Dana",
                                           updatedAt: Date().addingTimeInterval(-200 * 86_400)),
        contacts: [EmergencyContactInfo(id: "contact-rosa-dana", name: "Dana", relationship: "Daughter",
                                        phone: "(555) 014-2277")])

    static let walterDetail = CareReceiverInfo(
        id: HomeFixtures.walter.id, teamID: johnson.teamID, teamName: johnson.name, name: "Walter",
        timeZone: HomeFixtures.denver, isArchived: false, archivedByName: nil, archivedAt: nil,
        instructions: CareInstructionsInfo(body: "Walks after lunch, rain or shine.", updatedByName: "Ana Johnson",
                                           updatedAt: Date().addingTimeInterval(-3 * 86_400)),
        contacts: [EmergencyContactInfo(id: "contact-ana", name: "Ana Johnson", relationship: "Daughter",
                                        phone: "(555) 010-3344")])

    static let receiverDetails: [String: CareReceiverInfo] = [
        eleanorDetail.id: eleanorDetail, haroldDetail.id: haroldDetail, rosaDetail.id: rosaDetail,
        walterDetail.id: walterDetail,
    ]

    /// Trevor every Tuesday and Dana every Thursday, 8 AM to 4 PM.
    static let trevorRule = CoverageScheduleInfo(
        id: "coverage-trevor", receiverID: HomeFixtures.eleanor.id, userID: "user-trevor", caregiverName: "Trevor",
        days: [.tu], interval: 1, startTime: "08:00", endTime: "16:00", startsOn: nil, endsOn: nil)
    static let danaRule = CoverageScheduleInfo(
        id: "coverage-dana", receiverID: HomeFixtures.eleanor.id, userID: "user-dana", caregiverName: "Dana",
        days: [.th], interval: 1, startTime: "08:00", endTime: "16:00", startsOn: nil, endsOn: nil)

    /// The next `weekday` (1 = Sunday) on or after today in Eleanor's zone.
    private static func next(_ weekday: Int) -> LocalDay {
        var day = LocalDay(Date(), zone: HomeFixtures.chicago)
        while day.weekday != weekday { day = day.adding(days: 1) }
        return day
    }

    private static func assignment(_ id: String, _ who: TeamMemberInfo, on day: LocalDay, _ start: String,
                                   _ end: String, rule: String?) -> AssignmentInfo {
        let zone = HomeFixtures.chicago
        let starts = LocalDateTime(day: day, time: start)
        let ends = LocalDateTime(day: day, time: end)
        func at(_ t: LocalDateTime) -> Date {
            day.start(in: zone).addingTimeInterval(TimeInterval(t.minutes * 60))
        }
        return AssignmentInfo(id: id, receiverID: HomeFixtures.eleanor.id, userID: who.userID,
                              caregiverName: who.name, starts: starts, ends: ends, startsAt: at(starts),
                              endsAt: at(ends), coverageScheduleID: rule)
    }

    static var trevorTuesday: AssignmentInfo {
        assignment("assignment-tue", trevorMember, on: next(3), "08:00", "16:00", rule: trevorRule.id)
    }
    static var danaThursday: AssignmentInfo {
        assignment("assignment-thu", dana, on: next(5), "08:00", "16:00", rule: danaRule.id)
    }
    static var marcusSaturday: AssignmentInfo {
        assignment("assignment-sat", marcus, on: next(7), "09:00", "13:00", rule: nil)
    }
    /// On duty now (Figma's "Trevor is on duty until 4:00 PM").
    static var trevorNow: AssignmentInfo {
        assignment("assignment-now", trevorMember, on: LocalDay(Date(), zone: HomeFixtures.chicago), "00:00",
                   "16:00", rule: nil)
    }

    struct Unreachable: Error {}

    static func service(account: Account = trevor,
                        receiversByTeam: [String: [TeamReceiver]] = receiversByTeam,
                        invitations: [PendingInvitation] = GettingInFixtures.invitations,
                        redeem: RedeemOutcome = .joined,
                        detail: [String: TeamDetailInfo] = [riverside.teamID: riversideDetail,
                                                            johnson.teamID: johnsonDetail],
                        fail: Bool = false) -> TeamService {
        TeamService(
            account: { account },
            listInvitationsForMe: {
                if fail { throw Unreachable() }
                return invitations
            },
            redeem: { _ in redeem },
            createTeam: { name in .created(Account.Team(teamID: "team-new", name: name, role: "admin")) },
            listReceivers: { teamID, archived in
                if fail { throw Unreachable() }
                return (archived ? archivedByTeam : receiversByTeam)[teamID] ?? []
            },
            addReceiver: { _, name, zone in
                .added(TeamReceiver(id: "receiver-new", name: name, timeZone: zone))
            },
            team: { teamID in
                if fail { throw Unreachable() }
                guard let d = detail[teamID] else { throw AppError.forStatus(404, serverMessage: nil) }
                return d
            },
            listInvitations: { teamID in teamID == riverside.teamID ? [jordanInvitation] : [] },
            invite: { _, email in
                .created(TeamInvitationInfo(code: "NEW1-CODE-2345", email: email, invitedByName: "Trevor",
                                            createdAt: Date(), expiresAt: Date().addingTimeInterval(14 * 86_400)))
            },
            changeRole: { _, _, _ in .done },
            removeMember: { _, _ in .done },
            closeTeam: { _ in .closed },
            notifications: { _ in .allOn },
            changeNotifications: { _, choices in choices },
            careReceiver: { id in
                if fail { throw Unreachable() }
                guard let d = receiverDetails[id] else { throw AppError.forStatus(404, serverMessage: nil) }
                return d
            },
            changeReceiver: { id, name, zone in .done(TeamReceiver(id: id, name: name, timeZone: zone)) },
            archiveReceiver: { _ in },
            restoreReceiver: { _ in },
            changeInstructions: { id, body in
                guard let d = receiverDetails[id] else { return .refused }
                return .done(CareReceiverInfo(
                    id: d.id, teamID: d.teamID, teamName: d.teamName, name: d.name, timeZone: d.timeZone,
                    isArchived: false, archivedByName: nil, archivedAt: nil,
                    instructions: body.isEmpty ? nil : CareInstructionsInfo(body: body, updatedByName: "Trevor",
                                                                            updatedAt: Date()),
                    contacts: d.contacts))
            },
            changeContacts: { id, _ in receiverDetails[id].map { .done($0) } ?? .refused },
            onDuty: { id in id == HomeFixtures.eleanor.id ? [trevorNow] : [] },
            assignments: { id in
                id == HomeFixtures.eleanor.id || id == HomeFixtures.rosa.id
                    ? [trevorTuesday, danaThursday, marcusSaturday] : []
            },
            addAssignment: { _, _ in .done(marcusSaturday) },
            changeAssignment: { _, _ in .done(danaThursday) },
            removeAssignment: { _ in .done(Done()) },
            coverageSchedules: { id in
                id == HomeFixtures.eleanor.id || id == HomeFixtures.rosa.id ? [trevorRule, danaRule] : []
            },
            addCoverage: { _, _ in .done(trevorRule) },
            changeCoverage: { _, _ in .done(trevorRule) },
            removeCoverage: { _ in .done(Done()) }
        )
    }
}
#endif
