#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Trevor, The Riverside Group, and the
/// inbound Delgado Family invitation from Lucia. fixtures.md has one care team
/// Trevor is not on, so the list holds one invitation.
enum GettingInFixtures {
    static let trevorNoTeam = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [])

    static let trevorOnRiverside = Account(
        name: "Trevor",
        email: "twilliams0095@gmail.com",
        teams: [Account.Team(teamID: "team-riverside", name: "The Riverside Group", role: "admin")]
    )

    static let delgadoInvitation = PendingInvitation(code: "delgado-invite", teamName: "Delgado Family",
                                                     invitedByName: "Lucia")

    static let invitations = [delgadoInvitation]

    struct Unreachable: Error {}

    static func service(invitations: [PendingInvitation] = invitations,
                        invitationsFail: Bool = false,
                        redeem: RedeemOutcome = .joined,
                        createTeam: CreateTeamOutcome = .created) -> GettingInService {
        GettingInService(
            listInvitations: {
                if invitationsFail { throw Unreachable() }
                return invitations
            },
            redeem: { _ in redeem },
            createTeam: { _ in createTeam }
        )
    }
}
#endif
