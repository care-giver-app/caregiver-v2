import Foundation
import CaregiverAPI
import OpenAPIRuntime

/// The signed-in caregiver as Settings shows them (`Caregiver`).
struct SettingsAccount: Equatable, Sendable {
    var name: String
    var email: String
    /// Whether the app may reach them by email. On until changed.
    var emailNotifications: Bool
}

/// What kind of thing a piece of feedback is (`FeedbackRequest.kind`).
enum FeedbackKind: String, CaseIterable, Equatable, Sendable {
    case bug, suggestion, other
}

/// One message to the people behind the app (`FeedbackRequest`).
struct FeedbackDraft: Equatable, Sendable {
    let kind: FeedbackKind
    let message: String
    /// e.g. "2.0.0 (142)".
    let appVersion: String
    /// e.g. "iPhone 17, iOS 26.1".
    let device: String
}

/// A care team the caregiver is the only admin of, which refuses closing their account
/// (`SoleAdminTeam`).
struct SoleAdminTeamInfo: Equatable, Hashable, Identifiable, Sendable {
    let teamID: String
    let name: String
    /// Nobody else is on it, so there is nobody to promote: the team is closed first.
    let alone: Bool

    var id: String { teamID }
}

/// How `POST /v1/me/email` answered.
enum EmailChangeOutcome: Equatable, Sendable {
    /// 204 — a code went to the new address.
    case sent
    /// 403 — the current password is not right.
    case wrongPassword
    /// 409 — another account already uses that address.
    case emailInUse
    /// 429 — too many tries in a short time.
    case tooManyTries
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

/// How `POST /v1/me/close` answered.
enum CloseAccountOutcome: Equatable, Sendable {
    case closed
    case wrongPassword
    case tooManyTries
    /// 409 — the caregiver is the only admin of these care teams.
    case soleAdmin([SoleAdminTeamInfo])
}

/// How `POST /v1/feedback` answered.
enum FeedbackOutcome: Equatable, Sendable {
    case sent
    case tooManyTries
    case rejected(String?)
}

/// The `/v1` calls Settings makes, as closures so the models can be tested without a
/// network. Answers a screen branches on come back as outcomes; every other non-OK answer
/// is thrown as `AppError`. Unstubbed by default, so a test states the ones it reaches.
struct SettingsService: Sendable {
    /// `GET /v1/me` — the caregiver as the server has them now. The first request made with
    /// a token carrying a newly confirmed address copies it onto the account.
    var account: @Sendable () async throws -> SettingsAccount = { throw Unstubbed() }
    var changeName: @Sendable (_ name: String) async throws -> SettingsAccount = { _ in throw Unstubbed() }
    var changeEmailNotifications: @Sendable (_ on: Bool) async throws -> SettingsAccount
        = { _ in throw Unstubbed() }
    var startEmailChange: @Sendable (_ currentPassword: String, _ newEmail: String) async throws
        -> EmailChangeOutcome = { _, _ in throw Unstubbed() }
    var closeAccount: @Sendable (_ password: String) async throws -> CloseAccountOutcome
        = { _ in throw Unstubbed() }
    /// Anonymous sends go with no token at all, so nothing identifies the caregiver.
    var sendFeedback: @Sendable (_ draft: FeedbackDraft, _ anonymous: Bool) async throws -> FeedbackOutcome
        = { _, _ in throw Unstubbed() }

    struct Unstubbed: Error {}

    /// `client` signs every request with the caregiver's ID token; `anonymousClient` signs
    /// none, and carries only an anonymous Send feedback.
    static func live(_ client: Client, anonymousClient: Client) -> SettingsService {
        SettingsService(
            account: {
                switch try await client.getMyAccount() {
                case .ok(let ok): return SettingsAccount(try ok.body.json.caregiver)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            changeName: { name in
                try await change(client, .init(name: name))
            },
            changeEmailNotifications: { on in
                try await change(client, .init(emailNotifications: on))
            },
            startEmailChange: { password, email in
                switch try await client.startEmailChange(body: .json(.init(currentPassword: password,
                                                                           newEmail: email))) {
                case .noContent: return .sent
                case .forbidden: return .wrongPassword
                case .conflict: return .emailInUse
                case .tooManyRequests: return .tooManyTries
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            closeAccount: { password in
                switch try await client.closeMyAccount(body: .json(.init(password: password))) {
                case .noContent: return .closed
                case .forbidden: return .wrongPassword
                case .tooManyRequests: return .tooManyTries
                case .conflict(let conflict):
                    return .soleAdmin(try conflict.body.json.teams.map {
                        SoleAdminTeamInfo(teamID: $0.teamId, name: $0.name, alone: $0.alone)
                    })
                case .badRequest(let bad):
                    throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            sendFeedback: { draft, anonymous in
                let body = Components.Schemas.FeedbackRequest(
                    kind: .init(rawValue: draft.kind.rawValue) ?? .other, message: draft.message,
                    appVersion: draft.appVersion, device: draft.device)
                switch try await (anonymous ? anonymousClient : client).sendFeedback(body: .json(body)) {
                case .accepted: return .sent
                case .tooManyRequests: return .tooManyTries
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            }
        )
    }

    private static func change(_ client: Client, _ request: Components.Schemas.ChangeMyAccountRequest)
        async throws -> SettingsAccount {
        switch try await client.changeMyAccount(body: .json(request)) {
        case .ok(let ok): return SettingsAccount(try ok.body.json)
        case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
        case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
        case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
        }
    }
}

extension SettingsAccount {
    init(_ c: Components.Schemas.Caregiver) {
        self.init(name: c.name, email: c.email, emailNotifications: c.emailNotifications)
    }
}

/// Never a token: the anonymous Send feedback's client.
struct NoTokenProvider: TokenProvider {
    func idToken() async throws -> String? { nil }
}
