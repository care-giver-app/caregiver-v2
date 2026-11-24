import Foundation

/// The words the Team area shows, kept apart from the views so the models and tests use
/// the same ones (PRD "Team"; Figma "Team" page 450:3224).
enum TeamText {
    // MARK: Team

    static let yourCareTeams = "YOUR CARE TEAMS"
    static let waitingForYou = "WAITING FOR YOU"
    static let joinAnother = "JOIN ANOTHER CARE TEAM"
    static let pasteCode = "Paste an invite code"
    static let createTeam = "Create a care team"
    static let addReceiver = "Add care receiver"
    static let active = "Active"
    static let invitationsFailed = "Couldn't load your invitations."
    static let receiversFailed = "Couldn't load this team's care receivers."
    static let teamFailed = "Couldn't load your care teams."
    /// Figma 450:3458 — a proposal for the PRD's empty state, which names no words.
    static let noTeamsTitle = "You’re not on a care team"
    static let noTeamsLine = "Paste an invite code from a teammate, or start a team of your own."

    /// A pasted code that is invalid, expired, or already used: one answer for all (PRD).
    static let codeNoLongerValid = "That code is no longer valid."
    /// A listed invitation that expired or was used since the list appeared.
    static let invitationNoLongerValid = "That invitation is no longer valid."
    /// Accepting or pasting a code for a care team you already belong to (PRD).
    static let alreadyMember = "You’re already a member of that care team."

    static func role(_ role: String) -> String {
        role == "admin" ? "You’re an admin" : "You’re a caregiver"
    }

    static func invitedBy(_ name: String) -> String { "\(name) invited you" }

    // MARK: Care team

    static let caregivers = "CAREGIVERS"
    static let pendingInvitations = "PENDING INVITATIONS"
    static let archivedReceivers = "ARCHIVED CARE RECEIVERS"
    static let notifications = "NOTIFICATIONS"
    static let inviteCaregiver = "Invite a caregiver"
    static let notificationSettings = "Team notification settings"
    static let leave = "Leave this care team"
    static let close = "Close this care team"
    static let you = "You"
    static let copyCode = "Copy code"
    static let copied = "Copied"
    static let archived = "Archived"
    static let careTeamFailed = "Couldn't load this care team."
    static let invitationsListFailed = "Couldn't load the pending invitations."
    static let archivedFailed = "Couldn't load the archived care receivers."
    /// Figma 450:3740: the last admin trying to leave, refused with the reason (PRD).
    static let onlyAdminTitle = "You’re the only admin"
    static let onlyAdminLine = "Make someone else an admin before you leave."

    static func roleName(_ role: TeamRole) -> String { role == .admin ? "Admin" : "Caregiver" }

    static func summary(count: Int, myRole: TeamRole) -> String {
        let people = count == 1 ? "1 caregiver" : "\(count) caregivers"
        return "\(people) · " + (myRole == .admin ? "you’re an admin" : "you’re a caregiver")
    }

    /// "Expires in 7 days", by whole days left; "Expires today" inside the last one.
    static func expires(_ at: Date, now: Date) -> String {
        let days = Int((at.timeIntervalSince(now) / 86_400).rounded(.down))
        switch days {
        case ..<1: return "Expires today"
        case 1: return "Expires tomorrow"
        default: return "Expires in \(days) days"
        }
    }

    // MARK: Sheets

    static let newTeamTitle = "New care team"
    static let teamName = "Care team name"
    static let createTeamButton = "Create team"
    static let newReceiverTitle = "New care receiver"
    static let name = "Name"
    static let timeZone = "Time zone"
    static let addReceiverButton = "Add receiver"
    static let emailAddress = "Email address"
    /// Figma 450:3858: the app sends no email on the admin's behalf (PRD).
    static let inviteExplainer = "The app will provide a code specific to this email that is not "
        + "automatically shared. Copy and share the code."
    static let createInvitation = "Create invitation"
    /// Inviting an address that already belongs to someone on this care team (PRD).
    static let inviteeAlreadyMember = "That address already belongs to someone on this care team."
    static let makeAdmin = "Make admin"
    static let makeCaregiver = "Make caregiver"
    static let remove = "Remove from this care team"

    static func memberLine(_ role: TeamRole, team: String) -> String { "\(roleName(role)) on \(team)." }

    /// Demoting or removing the team's only admin, refused with the reason (PRD).
    static func lastAdmin(_ name: String) -> String {
        "\(name) is this team’s only admin. Make someone else an admin first."
    }

    static let leaveTitle = "Leave this care team?"
    /// What you lose — the access, and nothing else — and what stays (PRD).
    static let leaveLine = "You lose access to it. Every entry and journal note you wrote stays, under your name."
    static let leaveButton = "Leave"
    static let closeTitle = "Close this care team?"
    /// What goes and what stays (PRD "Close this care team?").
    static let closeLine = "Nobody will be able to reach this care team any longer, and its care receivers "
        + "go with it. Everything recorded in it is kept, not erased — only support can erase it, on request."
    static let closeButton = "Close team"
    /// 409 on Close team: someone else is on the team now.
    static let notLastCaregiver = "Someone else is on this care team now, so it can’t be closed."
    static let cancel = "Cancel"

    // MARK: Team notification settings

    static let reminders = "REMINDERS"
    static let alerts = "ALERTS"
    static let remindersRow = "Scheduled care coming up"
    static let rangeRow = "Readings outside their range"
    static let gapRow = "Trackers past their gap"
    static let unrecordedRow = "Care that goes unrecorded"
    static let notificationsFailed = "Couldn't load your notification settings."
    static let notificationsSaveFailed = "Couldn't save that change."

    // MARK: Time zones

    /// "Central time": the zone's generic name, lowercasing its trailing "Time".
    static func zoneName(_ zone: TimeZone) -> String {
        let name = zone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? zone.identifier
        return name.hasSuffix(" Time") ? String(name.dropLast(4)) + "time" : name
    }
}
