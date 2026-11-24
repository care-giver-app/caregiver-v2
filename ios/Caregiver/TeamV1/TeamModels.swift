import Foundation

/// A part of a screen read on its own, so one that fails says so where it goes without
/// taking the rest of the screen with it.
enum TeamPart<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
    case failed

    var value: Value? {
        if case .loaded(let v) = self { v } else { nil }
    }
}

/// Team (PRD "Team"; Figma 450:3226): every care team the caregiver belongs to with its
/// care receivers, the invitations waiting for their email, an invite code to paste, and a
/// team of their own. Scoped to the caregiver, not a care receiver, so switching receivers
/// leaves it exactly as it was.
///
/// `account` is the one place the app learns the caregiver's teams changed while signed
/// in: accepting, pasting a code, creating, leaving and closing each fetch `GET /v1/me`
/// again, and the tab shell hands the new account to Home.
@MainActor
@Observable
final class TeamListModel {
    struct TeamRows: Equatable, Identifiable {
        let team: Account.Team
        /// Active receivers, oldest first; archived ones live on Care team.
        var receivers: TeamPart<[TeamReceiver]>

        var id: String { team.teamID }
        var isAdmin: Bool { team.role == "admin" }
    }

    private(set) var account: Account
    private(set) var teams: [TeamRows]
    /// Never shown as an empty list when it failed: that would read as nobody having
    /// invited you.
    private(set) var invitations: TeamPart<[PendingInvitation]> = .loading
    /// Reading the caregiver's teams afresh failed; the teams last known stay on screen.
    private(set) var accountFailed = false

    /// The invite-code field is open (Figma 450:3372).
    var isPasting = false
    var code = ""
    /// The line under the invite-code field.
    private(set) var codeError: String?
    /// The line under the waiting invitations, for one that was refused.
    private(set) var invitationError: String?
    /// The invitation whose Accept is in flight, if any.
    private(set) var acceptingCode: String?
    private(set) var isJoining = false

    private let service: TeamService

    init(account: Account, service: TeamService) {
        self.account = account
        self.service = service
        teams = account.teams.map { TeamRows(team: $0, receivers: .loading) }
    }

    var isBusy: Bool { acceptingCode != nil || isJoining }
    var isEmpty: Bool { account.teams.isEmpty }

    /// Reads every team's receivers and the waiting invitations, side by side. What is
    /// already on screen stays until its answer replaces it, so coming back to the tab
    /// does not flash.
    func load() async {
        let service = service
        let teams = account.teams
        async let invitationsRead: [PendingInvitation]? = try? service.listInvitationsForMe()
        let receivers = await withTaskGroup(of: (String, [TeamReceiver]?).self) { group in
            for team in teams {
                group.addTask { (team.teamID, try? await service.listReceivers(team.teamID, false)) }
            }
            var byTeam: [String: [TeamReceiver]?] = [:]
            for await (id, list) in group { byTeam[id] = list }
            return byTeam
        }
        // Only teams still listed: one may have gone while this was reading.
        self.teams = self.account.teams.map { team in
            let previous = self.teams.first { $0.id == team.teamID }?.receivers
            guard let answered = receivers[team.teamID] else {
                return TeamRows(team: team, receivers: previous ?? .loading)
            }
            return TeamRows(team: team, receivers: answered.map {
                .loaded($0.map { $0.managed(by: team) })
            } ?? .failed)
        }
        if let read = await invitationsRead {
            invitations = .loaded(read)
        } else if invitations.value == nil {
            invitations = .failed
        }
    }

    func retryInvitations() async {
        invitations = .loading
        await load()
    }

    /// Reads the caregiver's teams again (`GET /v1/me`), then everything on them.
    func refreshAccount() async {
        do {
            let fresh = try await service.account()
            accountFailed = false
            adopt(fresh)
        } catch {
            accountFailed = true
        }
        await load()
    }

    /// Takes `account` as the teams the caregiver is on, keeping what is known of each.
    private func adopt(_ fresh: Account) {
        account = fresh
        teams = fresh.teams.map { team in
            TeamRows(team: team, receivers: teams.first { $0.id == team.teamID }?.receivers ?? .loading)
        }
    }

    // MARK: Joining

    /// Accept: the invitation becomes a care team on the list already here (PRD).
    func accept(_ invitation: PendingInvitation) async {
        guard !isBusy else { return }
        acceptingCode = invitation.code
        defer { acceptingCode = nil }
        invitationError = nil
        codeError = nil
        switch await redeem(invitation.code) {
        case .joined:
            await refreshAccount()
        case .alreadyMember:
            invitationError = TeamText.alreadyMember
        case .noLongerValid:
            // Stale since the list appeared: say so, and read the list again so the
            // dead row is not left there to be tapped twice.
            invitationError = TeamText.invitationNoLongerValid
            await load()
        case .rejected(let message):
            invitationError = AppError.forStatus(400, serverMessage: message).message
        case .failed(let error):
            invitationError = error.message
        }
    }

    /// Join, under the pasted code.
    func joinWithCode() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing pasted: the PRD names no message for this, so no call and no message.
        guard !trimmed.isEmpty, !isBusy else { return }
        isJoining = true
        defer { isJoining = false }
        invitationError = nil
        codeError = nil
        switch await redeem(trimmed) {
        case .joined:
            code = ""
            isPasting = false
            await refreshAccount()
        case .alreadyMember:
            codeError = TeamText.alreadyMember
        case .noLongerValid:
            codeError = TeamText.codeNoLongerValid
        case .rejected(let message):
            codeError = AppError.forStatus(400, serverMessage: message).message
        case .failed(let error):
            codeError = error.message
        }
    }

    func startPasting() {
        isPasting = true
        codeError = nil
    }

    private enum Redeemed {
        case joined, alreadyMember, noLongerValid, rejected(String?), failed(AppError)
    }

    private func redeem(_ code: String) async -> Redeemed {
        do {
            switch try await service.redeem(code) {
            case .joined: return .joined
            case .alreadyMember: return .alreadyMember
            case .noLongerValid: return .noLongerValid
            case .rejected(let message): return .rejected(message)
            }
        } catch {
            return .failed(AppError.from(error))
        }
    }

    // MARK: After a sheet

    /// Create a care team stays on Team: the row it becomes is the thing to act on next
    /// (PRD). Shown at once, then read afresh.
    func created(_ team: Account.Team) async {
        if !account.teams.contains(where: { $0.teamID == team.teamID }) {
            adopt(Account(name: account.name, email: account.email, teams: account.teams + [team],
                          userID: account.userID))
        }
        await refreshAccount()
    }
}

/// Create a care team (PRD; Figma 450:3519): one name; its creator becomes its first admin.
@MainActor
@Observable
final class CreateCareTeamModel {
    var name = ""
    private(set) var isCreating = false
    private(set) var error: String?

    private let service: TeamService

    init(service: TeamService) {
        self.service = service
    }

    var canCreate: Bool { !trimmed.isEmpty && !isCreating }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The new team, or nil with `error` set.
    func create() async -> Account.Team? {
        guard canCreate else { return nil }
        isCreating = true
        defer { isCreating = false }
        error = nil
        do {
            switch try await service.createTeam(trimmed) {
            case .created(let team): return team
            case .rejected(let message):
                error = AppError.forStatus(400, serverMessage: message).message
                return nil
            }
        } catch {
            self.error = AppError.from(error).message
            return nil
        }
    }
}

/// Add care receiver (PRD; Figma 450:3537): a name and the time zone every wall-clock time
/// about them is read in. Admins only, raised from Team or from Home with no receivers yet.
@MainActor
@Observable
final class AddCareReceiverModel {
    let team: Account.Team
    var name = ""
    var zone: TimeZone
    private(set) var isAdding = false
    private(set) var error: String?

    private let service: TeamService

    init(team: Account.Team, service: TeamService, zone: TimeZone = .current) {
        self.team = team
        self.service = service
        self.zone = zone
    }

    /// The zones offered: the continental US and its neighbours, plus this device's.
    var zones: [TimeZone] { Self.zones(including: zone) }

    var canAdd: Bool { !trimmed.isEmpty && !isAdding }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The new receiver, as the signed-in caregiver sees them, or nil with `error` set.
    func add() async -> TeamReceiver? {
        guard canAdd else { return nil }
        isAdding = true
        defer { isAdding = false }
        error = nil
        do {
            switch try await service.addReceiver(team.teamID, trimmed, zone) {
            case .added(let receiver): return receiver.managed(by: team)
            case .rejected(let message):
                error = AppError.forStatus(400, serverMessage: message).message
                return nil
            }
        } catch {
            self.error = AppError.from(error).message
            return nil
        }
    }

    nonisolated static let usZones = ["America/New_York", "America/Chicago", "America/Denver", "America/Phoenix",
                          "America/Los_Angeles", "America/Anchorage", "Pacific/Honolulu"]
        .compactMap(TimeZone.init(identifier:))

    nonisolated static func zones(including zone: TimeZone) -> [TimeZone] {
        usZones.contains(where: { $0.identifier == zone.identifier }) ? usZones : [zone] + usZones
    }

    /// A zone's name in the picker. Arizona says so: its generic name is Mountain
    /// Standard Time, which reads as a typo beside Mountain time.
    nonisolated static func label(_ zone: TimeZone) -> String {
        zone.identifier == "America/Phoenix" ? "Mountain time (Arizona)" : TeamText.zoneName(zone)
    }
}

/// Care team (PRD "Care team"; Figma 450:3560 admin, 450:3660 caregiver): who is on it,
/// who has been asked, its archived receivers, and the way out.
@MainActor
@Observable
final class CareTeamModel {
    let team: Account.Team
    let myUserID: String

    private(set) var detail: TeamPart<TeamDetailInfo> = .loading
    /// Admins only; never read for a caregiver.
    private(set) var invitations: TeamPart<[TeamInvitationInfo]> = .loading
    private(set) var archived: TeamPart<[TeamReceiver]> = .loading
    /// Leave was refused because they are the only admin (Figma 450:3740).
    private(set) var leaveRefused = false
    /// The code last copied, which reads "Copied" for a moment.
    private(set) var copiedCode: String?

    private let service: TeamService

    init(team: Account.Team, myUserID: String, service: TeamService) {
        self.team = team
        self.myUserID = myUserID
        self.service = service
    }

    var name: String { detail.value?.name ?? team.name }
    var isAdmin: Bool { (detail.value?.myRole ?? TeamRole(rawValue: team.role)) == .admin }
    var members: [TeamMemberInfo] { detail.value?.members ?? [] }
    var adminCount: Int { members.filter { $0.role == .admin }.count }
    /// The only admin can't leave, demote themselves, or be removed (PRD).
    var isOnlyAdmin: Bool { isAdmin && adminCount <= 1 }
    /// The last caregiver on it closes it rather than leaving (PRD).
    var isLastCaregiver: Bool { members.count == 1 && members.first.map(isMe) == true }

    func isMe(_ member: TeamMemberInfo) -> Bool { !myUserID.isEmpty && member.userID == myUserID }

    /// Whether a row opens anything: an admin opens anyone's, a caregiver only their own.
    func opens(_ member: TeamMemberInfo) -> Bool { isAdmin || isMe(member) }

    func load() async {
        let service = service
        let teamID = team.teamID
        async let archivedRead: [TeamReceiver]? = try? service.listReceivers(teamID, true)
        do {
            let detail = try await service.team(teamID)
            self.detail = .loaded(detail)
            if detail.myRole == .admin {
                if let read = try? await service.listInvitations(teamID) {
                    invitations = .loaded(read)
                } else if invitations.value == nil {
                    invitations = .failed
                }
            }
        } catch {
            if detail.value == nil { detail = .failed }
        }
        if let read = await archivedRead {
            archived = .loaded(read.map { $0.managed(by: team) })
        } else if archived.value == nil {
            archived = .failed
        }
    }

    func retry() async {
        detail = .loading
        await load()
    }

    /// Leave this care team, or your own row: true when Leave this care team? should
    /// open; the only admin is refused here, with the reason (PRD).
    func tryLeave() -> Bool {
        if isOnlyAdmin {
            leaveRefused = true
            return false
        }
        leaveRefused = false
        return true
    }

    /// Where your way out of the team goes, from your own row or the exit row: the last
    /// caregiver on it closes it, since nobody is left to hand it to; anyone else leaves,
    /// unless they are the only admin, who is refused with the reason (PRD). Nil when refused.
    func exitKind() -> LeaveTeamModel.Kind? {
        if isLastCaregiver {
            leaveRefused = false
            return .close
        }
        return tryLeave() ? .leave : nil
    }

    /// The server refused Leave because they are the only admin — the roster changed
    /// since it was read — so say so and read it again.
    func leaveWasRefused() async {
        leaveRefused = true
        await load()
    }

    /// Create invitation ends on the team, the invitation now a row with its code (PRD).
    func invitationCreated(_ invitation: TeamInvitationInfo) {
        let rest = invitations.value?.filter { $0.code != invitation.code } ?? []
        invitations = .loaded([invitation] + rest)
    }

    func copied(_ code: String) {
        copiedCode = code
    }

    func clearCopied(_ code: String) {
        if copiedCode == code { copiedCode = nil }
    }
}

/// Invite a caregiver (PRD; Figma 450:3844): an email address. Every invitation joins as a
/// caregiver, and the app sends no email — the admin copies the code.
@MainActor
@Observable
final class InviteCaregiverModel {
    let teamID: String
    var email = ""
    private(set) var isCreating = false
    private(set) var error: String?

    private let service: TeamService

    init(teamID: String, service: TeamService) {
        self.teamID = teamID
        self.service = service
    }

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canCreate: Bool { !trimmed.isEmpty && !isCreating }

    /// The new invitation, or nil with `error` set — refused when the address already
    /// belongs to someone on this team (PRD).
    func create() async -> TeamInvitationInfo? {
        guard canCreate else { return nil }
        isCreating = true
        defer { isCreating = false }
        error = nil
        do {
            switch try await service.invite(teamID, trimmed) {
            case .created(let invitation): return invitation
            case .alreadyMember:
                error = TeamText.inviteeAlreadyMember
                return nil
            case .rejected(let message):
                error = AppError.forStatus(400, serverMessage: message).message
                return nil
            }
        } catch {
            self.error = AppError.from(error).message
            return nil
        }
    }
}

/// A caregiver (PRD; Figma 450:3864): Make admin or Make caregiver, and Remove from this
/// care team, on one other caregiver's row. Admins only.
@MainActor
@Observable
final class MemberActionsModel {
    enum Action: Equatable { case makeAdmin, makeCaregiver, remove }

    let member: TeamMemberInfo
    let teamID: String
    let teamName: String
    /// They are the team's only admin, so demoting or removing them is refused.
    let isOnlyAdmin: Bool

    private(set) var working: Action?
    /// The reason an action was refused, or why it failed.
    private(set) var refusal: String?

    private let service: TeamService

    init(member: TeamMemberInfo, teamID: String, teamName: String, isOnlyAdmin: Bool, service: TeamService) {
        self.member = member
        self.teamID = teamID
        self.teamName = teamName
        self.isOnlyAdmin = isOnlyAdmin
        self.service = service
    }

    /// Make admin for a caregiver, Make caregiver for an admin.
    var roleAction: Action { member.role == .admin ? .makeCaregiver : .makeAdmin }

    /// True once done, so the sheet goes back to Care team.
    func perform(_ action: Action) async -> Bool {
        guard working == nil else { return false }
        refusal = nil
        if action != .makeAdmin, isOnlyAdmin {
            refusal = TeamText.lastAdmin(member.name)
            return false
        }
        working = action
        defer { working = nil }
        do {
            let outcome: MembershipOutcome
            switch action {
            case .makeAdmin: outcome = try await service.changeRole(teamID, member.userID, .admin)
            case .makeCaregiver: outcome = try await service.changeRole(teamID, member.userID, .caregiver)
            case .remove: outcome = try await service.removeMember(teamID, member.userID)
            }
            switch outcome {
            case .done: return true
            case .lastAdmin:
                refusal = TeamText.lastAdmin(member.name)
                return false
            }
        } catch {
            refusal = AppError.from(error).message
            return false
        }
    }
}

/// Leave this care team? and Close this care team? (PRD; Figma 450:3886): what goes and
/// what stays, then the one way out or Cancel.
@MainActor
@Observable
final class LeaveTeamModel {
    enum Kind: Equatable { case leave, close }
    enum Outcome: Equatable {
        /// Gone from the team: back to Team.
        case left
        /// Leave refused: they are its only admin.
        case onlyAdmin
    }

    let kind: Kind
    let teamID: String
    let myUserID: String
    private(set) var isWorking = false
    private(set) var failure: String?

    private let service: TeamService

    init(kind: Kind, teamID: String, myUserID: String, service: TeamService) {
        self.kind = kind
        self.teamID = teamID
        self.myUserID = myUserID
        self.service = service
    }

    /// How it went, or nil with `failure` set and the sheet still up.
    func confirm() async -> Outcome? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        failure = nil
        do {
            switch kind {
            case .leave:
                switch try await service.removeMember(teamID, myUserID) {
                case .done: return .left
                case .lastAdmin: return .onlyAdmin
                }
            case .close:
                switch try await service.closeTeam(teamID) {
                case .closed: return .left
                case .notLastCaregiver:
                    failure = TeamText.notLastCaregiver
                    return nil
                }
            }
        } catch {
            failure = AppError.from(error).message
            return nil
        }
    }
}

/// Team notification settings (PRD; Figma 450:3901): which kinds of reminder and alert
/// this team sends the signed-in caregiver. Each switch saves as it is turned.
@MainActor
@Observable
final class TeamNotificationsModel {
    let team: Account.Team
    private(set) var choices: TeamPart<TeamNotificationChoices> = .loading
    private(set) var saveFailed = false
    private(set) var isSaving = false

    private let service: TeamService

    init(team: Account.Team, service: TeamService) {
        self.team = team
        self.service = service
    }

    func load() async {
        do {
            choices = .loaded(try await service.notifications(team.teamID))
        } catch {
            if choices.value == nil { choices = .failed }
        }
    }

    func retry() async {
        choices = .loading
        await load()
    }

    /// Turns one kind on or off. Shown at once; put back, with a line saying so, if the
    /// change didn't save.
    func set(_ kind: WritableKeyPath<TeamNotificationChoices, Bool>, to on: Bool) async {
        guard var next = choices.value, next[keyPath: kind] != on else { return }
        let before = next
        next[keyPath: kind] = on
        choices = .loaded(next)
        saveFailed = false
        isSaving = true
        defer { isSaving = false }
        do {
            choices = .loaded(try await service.changeNotifications(team.teamID, next))
        } catch {
            choices = .loaded(before)
            saveFailed = true
        }
    }
}
