import Foundation
import CaregiverAPI
import OpenAPIRuntime

/// A role on one care team (`Role`).
enum TeamRole: String, Equatable, Hashable, Sendable {
    case admin, caregiver
}

/// One caregiver on a care team's roster (`TeamMember`).
struct TeamMemberInfo: Equatable, Hashable, Identifiable, Sendable {
    let userID: String
    let name: String
    let role: TeamRole

    var id: String { userID }
}

/// One care team, its name and who is on it (`TeamDetail`). Only the people on it now:
/// what a former teammate looks like is an open gap in the PRD.
struct TeamDetailInfo: Equatable, Sendable {
    let teamID: String
    let name: String
    let myRole: TeamRole
    /// Admins first, then by name.
    let members: [TeamMemberInfo]
}

/// An invitation not yet used and not yet expired, with its code to copy (`TeamInvitation`).
struct TeamInvitationInfo: Equatable, Hashable, Identifiable, Sendable {
    let code: String
    let email: String
    let invitedByName: String
    let createdAt: Date
    let expiresAt: Date

    var id: String { code }
}

/// Which kinds of reminder and alert one care team sends the signed-in caregiver
/// (`NotificationChoices`). All on until changed.
struct TeamNotificationChoices: Equatable, Sendable {
    var reminders: Bool
    var rangeAlerts: Bool
    var gapAlerts: Bool
    var unrecordedAlerts: Bool

    static let allOn = TeamNotificationChoices(reminders: true, rangeAlerts: true, gapAlerts: true,
                                               unrecordedAlerts: true)
}

/// How `POST /v1/teams/{id}/invitations` answered.
enum InviteOutcome: Equatable, Sendable {
    case created(TeamInvitationInfo)
    /// 409 — that address already belongs to someone on this care team.
    case alreadyMember
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

/// How a change to someone's place on a team answered — Make admin, Make caregiver,
/// Remove, or Leave (`PUT`/`DELETE /v1/teams/{id}/members/{userId}`).
enum MembershipOutcome: Equatable, Sendable {
    case done
    /// 409 — a care team always has an admin, and this would leave it without one.
    case lastAdmin
}

/// How `POST /v1/teams/{id}/close` answered.
enum CloseTeamOutcome: Equatable, Sendable {
    case closed
    /// 409 — someone else is on the team now, so it is theirs to keep; leave instead.
    case notLastCaregiver
}

/// How `POST /v1/teams` answered on Team.
enum NewTeamOutcome: Equatable, Sendable {
    case created(Account.Team)
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

/// How `POST /v1/teams/{id}/receivers` answered.
enum AddReceiverOutcome: Equatable, Sendable {
    case added(TeamReceiver)
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

/// The `/v1` calls the Team area makes, as closures so the models can be tested without a
/// network. Answers a screen branches on come back as outcomes; every other non-OK answer
/// is thrown as `AppError`. Unstubbed by default, so a test states the ones it reaches.
struct TeamService: Sendable {
    /// `GET /v1/me` — the caregiver and the care teams they belong to now.
    var account: @Sendable () async throws -> Account = { throw Unstubbed() }
    var listInvitationsForMe: @Sendable () async throws -> [PendingInvitation] = { throw Unstubbed() }
    var redeem: @Sendable (_ code: String) async throws -> RedeemOutcome = { _ in throw Unstubbed() }
    var createTeam: @Sendable (_ name: String) async throws -> NewTeamOutcome = { _ in throw Unstubbed() }
    /// Active receivers, or the archived ones when `archived`.
    var listReceivers: @Sendable (_ teamID: String, _ archived: Bool) async throws -> [TeamReceiver]
        = { _, _ in throw Unstubbed() }
    var addReceiver: @Sendable (_ teamID: String, _ name: String, _ zone: TimeZone) async throws
        -> AddReceiverOutcome = { _, _, _ in throw Unstubbed() }
    var team: @Sendable (_ teamID: String) async throws -> TeamDetailInfo = { _ in throw Unstubbed() }
    var listInvitations: @Sendable (_ teamID: String) async throws -> [TeamInvitationInfo]
        = { _ in throw Unstubbed() }
    var invite: @Sendable (_ teamID: String, _ email: String) async throws -> InviteOutcome
        = { _, _ in throw Unstubbed() }
    var changeRole: @Sendable (_ teamID: String, _ userID: String, _ role: TeamRole) async throws
        -> MembershipOutcome = { _, _, _ in throw Unstubbed() }
    /// Removes someone — or, with the caller's own id, leaves.
    var removeMember: @Sendable (_ teamID: String, _ userID: String) async throws -> MembershipOutcome
        = { _, _ in throw Unstubbed() }
    var closeTeam: @Sendable (_ teamID: String) async throws -> CloseTeamOutcome = { _ in throw Unstubbed() }
    var notifications: @Sendable (_ teamID: String) async throws -> TeamNotificationChoices
        = { _ in throw Unstubbed() }
    var changeNotifications: @Sendable (_ teamID: String, _ choices: TeamNotificationChoices) async throws
        -> TeamNotificationChoices = { _, _ in throw Unstubbed() }

    // Care receiver (`CareReceiverService.swift`). Every member reads; admins write, and
    // an archived receiver's writes answer `.refused`.

    var careReceiver: @Sendable (_ receiverID: String) async throws -> CareReceiverInfo = { _ in throw Unstubbed() }
    var changeReceiver: @Sendable (_ receiverID: String, _ name: String, _ zone: TimeZone) async throws
        -> ReceiverWriteOutcome<TeamReceiver> = { _, _, _ in throw Unstubbed() }
    var archiveReceiver: @Sendable (_ receiverID: String) async throws -> Void = { _ in throw Unstubbed() }
    var restoreReceiver: @Sendable (_ receiverID: String) async throws -> Void = { _ in throw Unstubbed() }
    /// An empty body clears them.
    var changeInstructions: @Sendable (_ receiverID: String, _ body: String) async throws
        -> ReceiverWriteOutcome<CareReceiverInfo> = { _, _ in throw Unstubbed() }
    /// The whole list, in order, replacing the one there.
    var changeContacts: @Sendable (_ receiverID: String, _ contacts: [EmergencyContactWrite]) async throws
        -> ReceiverWriteOutcome<CareReceiverInfo> = { _, _ in throw Unstubbed() }
    /// Every assignment covering this moment; empty when nobody is on duty.
    var onDuty: @Sendable (_ receiverID: String) async throws -> [AssignmentInfo] = { _ in throw Unstubbed() }
    /// Every assignment not yet ended, soonest first.
    var assignments: @Sendable (_ receiverID: String) async throws -> [AssignmentInfo] = { _ in throw Unstubbed() }
    var addAssignment: @Sendable (_ receiverID: String, _ write: AssignmentWrite) async throws
        -> ReceiverWriteOutcome<AssignmentInfo> = { _, _ in throw Unstubbed() }
    var changeAssignment: @Sendable (_ assignmentID: String, _ write: AssignmentWrite) async throws
        -> ReceiverWriteOutcome<AssignmentInfo> = { _, _ in throw Unstubbed() }
    var removeAssignment: @Sendable (_ assignmentID: String) async throws -> ReceiverWriteOutcome<Done>
        = { _ in throw Unstubbed() }
    /// Rules not removed, ended or not.
    var coverageSchedules: @Sendable (_ receiverID: String) async throws -> [CoverageScheduleInfo]
        = { _ in throw Unstubbed() }
    var addCoverage: @Sendable (_ receiverID: String, _ write: CoverageScheduleWrite) async throws
        -> ReceiverWriteOutcome<CoverageScheduleInfo> = { _, _ in throw Unstubbed() }
    var changeCoverage: @Sendable (_ scheduleID: String, _ write: CoverageScheduleWrite) async throws
        -> ReceiverWriteOutcome<CoverageScheduleInfo> = { _, _ in throw Unstubbed() }
    var removeCoverage: @Sendable (_ scheduleID: String) async throws -> ReceiverWriteOutcome<Done>
        = { _ in throw Unstubbed() }

    struct Unstubbed: Error {}

    static func live(_ client: Client) -> TeamService {
        TeamService(
            account: {
                switch try await client.getMyAccount() {
                case .ok(let ok): return Account(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            listInvitationsForMe: {
                switch try await client.listInvitationsForMe() {
                case .ok(let ok):
                    return try ok.body.json.map {
                        PendingInvitation(code: $0.code, teamName: $0.teamName, invitedByName: $0.invitedByName)
                    }
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
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
                case .created(let created):
                    let m = try created.body.json
                    return .created(Account.Team(teamID: m.teamId, name: m.name, role: m.role.rawValue))
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            listReceivers: { teamID, archived in
                switch try await client.listTeamReceivers(path: .init(teamId: teamID),
                                                          query: .init(status: archived ? .archived : .active)) {
                case .ok(let ok): return try ok.body.json.map(TeamReceiver.init)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            addReceiver: { teamID, name, zone in
                switch try await client.addCareReceiver(path: .init(teamId: teamID),
                                                        body: .json(.init(name: name, timeZone: zone.identifier))) {
                case .created(let created): return .added(TeamReceiver(try created.body.json))
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            team: { teamID in
                switch try await client.getTeam(path: .init(teamId: teamID)) {
                case .ok(let ok): return TeamDetailInfo(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            listInvitations: { teamID in
                switch try await client.listTeamInvitations(path: .init(teamId: teamID)) {
                case .ok(let ok): return try ok.body.json.map(TeamInvitationInfo.init)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            invite: { teamID, email in
                switch try await client.inviteCaregiver(path: .init(teamId: teamID), body: .json(.init(email: email))) {
                case .created(let created): return .created(TeamInvitationInfo(try created.body.json))
                case .conflict: return .alreadyMember
                case .badRequest(let bad): return .rejected(try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            changeRole: { teamID, userID, role in
                let r: Components.Schemas.Role = role == .admin ? .admin : .caregiver
                switch try await client.changeRole(path: .init(teamId: teamID, userId: userID),
                                                   body: .json(.init(role: r))) {
                case .ok: return .done
                case .conflict: return .lastAdmin
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            removeMember: { teamID, userID in
                switch try await client.removeMember(path: .init(teamId: teamID, userId: userID)) {
                case .noContent: return .done
                case .conflict: return .lastAdmin
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            closeTeam: { teamID in
                switch try await client.closeTeam(path: .init(teamId: teamID)) {
                case .noContent: return .closed
                case .conflict: return .notLastCaregiver
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            notifications: { teamID in
                switch try await client.getMyTeamNotifications(path: .init(teamId: teamID)) {
                case .ok(let ok): return TeamNotificationChoices(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            changeNotifications: { teamID, choices in
                switch try await client.changeMyTeamNotifications(path: .init(teamId: teamID),
                                                                  body: .json(choices.schema)) {
                case .ok(let ok): return TeamNotificationChoices(try ok.body.json)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            }
        ).withReceiver(client)
    }
}

// MARK: - Mapping from the generated types

extension Account {
    init(_ a: Components.Schemas.MyAccount) {
        self.init(name: a.caregiver.name, email: a.caregiver.email,
                  teams: a.teams.map { Account.Team(teamID: $0.teamId, name: $0.name, role: $0.role.rawValue) },
                  userID: a.caregiver.userId)
    }
}

extension TeamRole {
    init(_ r: Components.Schemas.Role) {
        self = r == .admin ? .admin : .caregiver
    }
}

extension TeamDetailInfo {
    init(_ t: Components.Schemas.TeamDetail) {
        self.init(teamID: t.teamId, name: t.name, myRole: TeamRole(t.myRole),
                  members: t.members.map { TeamMemberInfo(userID: $0.userId, name: $0.name, role: TeamRole($0.role)) })
    }
}

extension TeamInvitationInfo {
    init(_ i: Components.Schemas.TeamInvitation) {
        self.init(code: i.code, email: i.email, invitedByName: i.invitedByName, createdAt: i.createdAt,
                  expiresAt: i.expiresAt)
    }
}

extension TeamNotificationChoices {
    init(_ c: Components.Schemas.NotificationChoices) {
        self.init(reminders: c.reminders, rangeAlerts: c.rangeAlerts, gapAlerts: c.gapAlerts,
                  unrecordedAlerts: c.unrecordedAlerts)
    }

    var schema: Components.Schemas.NotificationChoices {
        .init(reminders: reminders, rangeAlerts: rangeAlerts, gapAlerts: gapAlerts,
              unrecordedAlerts: unrecordedAlerts)
    }
}
