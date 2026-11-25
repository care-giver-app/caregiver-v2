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
    static let switchReceiver = "Switch"
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

    // MARK: Care receiver

    static let careInstructions = "CARE INSTRUCTIONS"
    static let emergencyContacts = "EMERGENCY CONTACTS"
    static let whoIsMeantToBeThere = "WHO IS MEANT TO BE THERE"
    static let assignmentsAhead = "ASSIGNMENTS AHEAD"
    static let coverageSchedules = "COVERAGE SCHEDULES"
    static let edit = "Edit"
    static let add = "Add"
    static let call = "Call"
    /// Figma 451:3553 — the proposal for the PRD's three empty parts: one muted line each,
    /// and for an admin the way to add one.
    static let noInstructions = "No care instructions yet."
    static let noContacts = "No emergency contacts yet."
    static let nobodyAssigned = "Nobody is assigned."
    /// One group empty while the other is not — not in the PRD or Figma, which show both
    /// groups full or both empty.
    static let noAssignmentsAhead = "No assignments ahead."
    static let noCoverageSchedules = "No coverage schedules."
    static let writeInstructions = "Write care instructions"
    static let addContact = "Add a contact"
    static let addAssignment = "Add an assignment"
    static let addCoverage = "Add a coverage schedule"
    /// A roster that has nobody on duty this minute. Not in the PRD or Figma, which show
    /// only someone on duty and a team with no roster at all.
    static let nobodyOnDuty = "Nobody is on duty right now."
    static let archiveReceiver = "Archive this care receiver"
    static let restoreReceiver = "Restore this care receiver"
    static let careReceiverFailed = "Couldn't load this care receiver."
    static let onDutyFailed = "Couldn't load who is on duty."
    static let assignmentsFailed = "Couldn't load the assignments."
    static let coverageFailed = "Couldn't load the coverage schedules."
    static let restoreFailed = "Couldn't restore them."

    /// "Central time · The Riverside Group".
    static func identityLine(zone: TimeZone, team: String) -> String { "\(zoneName(zone)) · \(team)" }

    /// "Changed by Trevor · Aug 14" — the stamp on the written instructions alone.
    static func changedBy(_ name: String, at: Date, now: Date, zone: TimeZone) -> String {
        "Changed by \(name) · \(shortDate(at, now: now, zone: zone))"
    }

    /// "Archived by Dana · Aug 3. Everything here is kept, and read-only until an admin
    /// restores them."
    static func archivedLine(by name: String?, at: Date?, now: Date, zone: TimeZone) -> String {
        var head = "Archived"
        if let name { head += " by \(name)" }
        if let at { head += " · \(shortDate(at, now: now, zone: zone))" }
        return head + ". Everything here is kept, and read-only until an admin restores them."
    }

    /// "Daughter · (555) 014-2277"; the number alone when no relationship was given.
    static func contactLine(_ c: EmergencyContactInfo) -> String {
        let relationship = c.relationship.trimmingCharacters(in: .whitespaces)
        return relationship.isEmpty ? c.phone : "\(relationship) · \(c.phone)"
    }

    static func onDuty(_ name: String) -> String { "\(name) is on duty" }

    /// "until 4:00 PM" today, "until 8:00 AM tomorrow", else "until Tue, Oct 27, 8:00 AM".
    static func until(_ ends: LocalDateTime, now: LocalDateTime) -> String {
        if ends.day == now.day { return "until \(TrackerText.clock(ends.time))" }
        if ends.day == now.day.adding(days: 1) { return "until \(TrackerText.clock(ends.time)) tomorrow" }
        return "until \(dayLabel(ends.day)), \(TrackerText.clock(ends.time))"
    }

    /// "8:00 AM – 4:00 PM".
    static func hours(_ start: String, _ end: String) -> String {
        "\(TrackerText.clock(start)) – \(TrackerText.clock(end))"
    }

    /// "Tue, Oct 27 · 8:00 AM – 4:00 PM"; one running overnight reads the same, since
    /// its end is earlier than its start. Longer than that names both days.
    static func assignmentLine(_ a: AssignmentInfo) -> String {
        if a.ends.day <= a.starts.day.adding(days: 1), a.ends.day == a.starts.day || a.ends.minutes <= a.starts.minutes {
            return "\(dayLabel(a.starts.day)) · \(hours(a.starts.time, a.ends.time))"
        }
        return "\(dayLabel(a.starts.day)), \(TrackerText.clock(a.starts.time)) – "
            + "\(dayLabel(a.ends.day)), \(TrackerText.clock(a.ends.time))"
    }

    /// "Every Tuesday", "Every Tuesday and Thursday", "Every Mon, Wed, Fri", "Every day";
    /// "Every 2 weeks on Tuesday" for a longer interval.
    static func coverageTitle(days: [ScheduleWeekday], interval: Int) -> String {
        let set = Set(days).sorted()
        let when: String
        if set.count == ScheduleWeekday.allCases.count {
            when = "day"
        } else if set.count == 1 {
            when = dayName(set[0])
        } else if set.count == 2 {
            when = "\(dayName(set[0])) and \(dayName(set[1]))"
        } else {
            when = TrackerText.days(set)
        }
        if interval <= 1 { return "Every \(when)" }
        return when == "day" ? "Every day, every \(interval) weeks" : "Every \(interval) weeks on \(when)"
    }

    /// "Trevor · 8:00 AM – 4:00 PM", with " · until Dec 1" or " · ended Nov 1" when it ends.
    static func coverageLine(_ c: CoverageScheduleInfo, today: LocalDay) -> String {
        var line = "\(c.caregiverName) · \(hours(c.startTime, c.endTime))"
        if let ends = c.endsOn {
            line += ends < today ? " · ended \(monthDay(ends, today: today))" : " · until \(monthDay(ends, today: today))"
        }
        return line
    }

    /// The caption under an assignment a coverage schedule made: "From the Thursday
    /// coverage schedule. Changing this day leaves the schedule as it is." (Figma 451:3769).
    static func fromRule(_ rule: CoverageScheduleInfo?) -> String {
        let which = rule.map { "the \(Set($0.days).count == 1 ? dayName($0.days[0]) : TrackerText.days($0.days)) " }
            ?? "a "
        return "From \(which)coverage schedule. Changing this day leaves the schedule as it is."
    }

    static func dayName(_ d: ScheduleWeekday) -> String {
        switch d {
        case .mo: "Monday"
        case .tu: "Tuesday"
        case .we: "Wednesday"
        case .th: "Thursday"
        case .fr: "Friday"
        case .sa: "Saturday"
        case .su: "Sunday"
        }
    }

    /// "Tue, Oct 27".
    static func dayLabel(_ day: LocalDay) -> String {
        let utc = TimeZone(identifier: "UTC")!
        return TrackerText.format(day.start(in: utc), "EEE, MMM d", utc)
    }

    /// "Dec 1", or "Dec 1, 2027" outside `today`'s year.
    static func monthDay(_ day: LocalDay, today: LocalDay) -> String {
        let utc = TimeZone(identifier: "UTC")!
        return TrackerText.format(day.start(in: utc), day.year == today.year ? "MMM d" : "MMM d, yyyy", utc)
    }

    private static func shortDate(_ date: Date, now: Date, zone: TimeZone) -> String {
        monthDay(LocalDay(date, zone: zone), today: LocalDay(now, zone: zone))
    }

    // MARK: Care receiver's sheets

    static let editReceiverTitle = "Edit care receiver"
    static let instructionsTitle = "Care instructions"
    static let contactsTitle = "Emergency contacts"
    static let assignmentTitle = "Assignment"
    static let coverageTitle = "Coverage schedule"
    static let save = "Save"
    static let relationship = "Relationship"
    static let phone = "Phone"
    static let caregiver = "Caregiver"
    static let day = "Day"
    static let days = "Days"
    static let starts = "Starts"
    static let ends = "Ends"
    static let repeatsUntil = "Repeats until"
    static let forever = "Forever"
    static let onADate = "On a date"
    static let lastDay = "Last day"
    static let chooseCaregiver = "Choose…"
    static let removeButton = "Remove"
    static let archiveButton = "Archive"
    /// Figma 451:3734.
    static let dragToReorder = "Drag to change the order caregivers see."
    static let newContact = "New contact"
    static let membersFailed = "Couldn't load who is on this care team."

    static let archiveTitle = "Archive this care receiver?"
    /// What stops and what stays (PRD "Archive this care receiver?").
    static func archiveLine(_ name: String) -> String {
        "\(name) leaves Home, Team’s list of care receivers, and Quick log. Their schedules stop, and nothing "
            + "about them reminds or alerts anyone. Everything recorded about them stays, readable from Team, "
            + "and an admin can restore them."
    }

    static let removeCoverageTitle = "Remove this coverage schedule?"
    /// Figma 451:3837: what goes — the rule and its assignments still ahead — and what stays.
    static let removeCoverageLine = "This will remove all future instances of the coverage schedule. Past days "
        + "are unaffected and still show who was responsible."

    /// 409 on any write about an archived receiver.
    static func archivedRefusal(_ name: String) -> String {
        "\(name) is archived, so nothing about them can be changed until an admin restores them."
    }

    /// 409 on an assignment: it has ended, or the receiver was archived — the API doesn't say which.
    static let assignmentRefused = "This assignment can’t be changed: it has already ended, or the care "
        + "receiver has been archived."

    // MARK: Time zones

    /// "Central time": the zone's generic name, lowercasing its trailing "Time".
    static func zoneName(_ zone: TimeZone) -> String {
        let name = zone.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? zone.identifier
        return name.hasSuffix(" Time") ? String(name.dropLast(4)) + "time" : name
    }
}
