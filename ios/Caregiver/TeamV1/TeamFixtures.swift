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
            changeNotifications: { _, choices in choices }
        )
    }
}
#endif
