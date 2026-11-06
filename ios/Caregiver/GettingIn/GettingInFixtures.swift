#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Trevor, The Riverside Group, Johnson Family,
/// and the roster's Dana and Marcus as inviters (as drawn in Figma 358:3354).
enum GettingInFixtures {
    static let trevorNoTeam = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [])

    static let trevorOnRiverside = Account(
        name: "Trevor",
        email: "twilliams0095@gmail.com",
        teams: [Account.Team(teamID: "team-riverside", name: "The Riverside Group", role: "admin")]
    )

    static let invitations = [
        PendingInvitation(code: "riverside-invite", teamName: "The Riverside Group", invitedByName: "Dana"),
        PendingInvitation(code: "johnson-invite", teamName: "Johnson Family", invitedByName: "Marcus"),
    ]

    static func service(invitations: [PendingInvitation] = invitations,
                        redeem: RedeemOutcome = .joined,
                        createTeam: CreateTeamOutcome = .created) -> GettingInService {
        GettingInService(
            listInvitations: { invitations },
            redeem: { _ in redeem },
            createTeam: { _ in createTeam }
        )
    }
}
#endif
