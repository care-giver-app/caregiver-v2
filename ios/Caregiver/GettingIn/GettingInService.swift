import Foundation
import CaregiverAPI

/// An invitation waiting for the signed-in caregiver's email (`GET /v1/me/invitations`).
struct PendingInvitation: Equatable, Identifiable, Sendable {
    let code: String
    let teamName: String
    let invitedByName: String
    var id: String { code }
}

/// How `POST /v1/invitations/redeem` answered.
enum RedeemOutcome: Equatable, Sendable {
    case joined
    /// 410 — unknown, expired, already used, or revoked; one answer for all four.
    case noLongerValid
    /// 409 — the caller already belongs to this care team.
    case alreadyMember
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

/// How `POST /v1/teams` answered.
enum CreateTeamOutcome: Equatable, Sendable {
    case created
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

/// The `/v1` calls Join a care team and Create your first care team make, as
/// closures so the models can be tested without a network. Statuses a screen
/// does not branch on (401, undocumented) are thrown as `AppError`.
struct GettingInService: Sendable {
    var listInvitations: @Sendable () async throws -> [PendingInvitation]
    var redeem: @Sendable (_ code: String) async throws -> RedeemOutcome
    var createTeam: @Sendable (_ name: String) async throws -> CreateTeamOutcome

    static func live(_ client: Client) -> GettingInService {
        GettingInService(
            listInvitations: {
                switch try await client.listInvitationsForMe() {
                case .ok(let ok):
                    return try ok.body.json.map {
                        PendingInvitation(code: $0.code, teamName: $0.teamName, invitedByName: $0.invitedByName)
                    }
                case .unauthorized:
                    throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _):
                    throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            redeem: { code in
                switch try await client.redeemInvitation(body: .json(.init(code: code))) {
                case .ok: return .joined
                case .gone: return .noLongerValid
                case .conflict: return .alreadyMember
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            createTeam: { name in
                switch try await client.createTeam(body: .json(.init(name: name))) {
                case .created: return .created
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            }
        )
    }
}
