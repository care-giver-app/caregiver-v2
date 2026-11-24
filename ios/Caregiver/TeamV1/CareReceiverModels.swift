import Foundation

/// Care receiver (PRD "Care receiver"; Figma 451:3428, 451:3553 just added): everything about
/// the person that is not an entry — their instructions, who to call, who is meant to be
/// there. Every caregiver reads all of it; only admins change any of it, and nobody changes
/// anything while they are archived. Reached from Team's chevron, Care team's archived list,
/// and Home's header.
@MainActor
@Observable
final class CareReceiverModel {
    /// Who was pushed; the name and zone until the detail answers.
    private(set) var receiver: TeamReceiver
    private(set) var detail: TeamPart<CareReceiverInfo> = .loading
    private(set) var onDuty: TeamPart<[AssignmentInfo]> = .loading
    private(set) var assignments: TeamPart<[AssignmentInfo]> = .loading
    private(set) var coverage: TeamPart<[CoverageScheduleInfo]> = .loading
    /// Who an assignment or a coverage schedule can name: the team's caregivers now. Read
    /// only for an admin, who is the only one who can open those sheets.
    private(set) var members: TeamPart<[TeamMemberInfo]> = .loading
    private(set) var isRestoring = false
    /// Why Restore failed, shown in place of its row.
    private(set) var restoreError: String?

    private let service: TeamService
    private let clock: @MainActor () -> Date

    init(receiver: TeamReceiver, service: TeamService, clock: @escaping @MainActor () -> Date = Date.init) {
        self.receiver = receiver
        self.service = service
        self.clock = clock
    }

    var name: String { detail.value?.name ?? receiver.name }
    var zone: TimeZone { detail.value?.timeZone ?? receiver.timeZone }
    var isAdmin: Bool { receiver.canManage }
    var isArchived: Bool { detail.value?.isArchived ?? false }
    /// Every write is an admin's, and none is open on an archived receiver (PRD).
    var canWrite: Bool { isAdmin && !isArchived && detail.value != nil }
    var now: Date { clock() }
    var today: LocalDay { LocalDay(clock(), zone: zone) }
    var localNow: LocalDateTime { LocalDateTime(clock(), zone: zone) }

    /// The team keeps no roster for them: no assignment ahead and no rule. One line says
    /// nobody is assigned (PRD).
    var keepsNoRoster: Bool {
        assignments.value?.isEmpty == true && coverage.value?.isEmpty == true
    }

    /// The rule that made `assignment`, when it is still listed.
    func rule(for assignment: AssignmentInfo) -> CoverageScheduleInfo? {
        guard let id = assignment.coverageScheduleID else { return nil }
        return coverage.value?.first { $0.id == id }
    }

    /// Everything, side by side; a part that fails says so where it goes. What is on
    /// screen stays until its answer replaces it.
    func load() async {
        let service = service
        let id = receiver.id
        async let detailRead = Self.capture { try await service.careReceiver(id) }
        async let onDutyRead = Self.capture { try await service.onDuty(id) }
        async let assignmentsRead = Self.capture { try await service.assignments(id) }
        async let coverageRead = Self.capture { try await service.coverageSchedules(id) }
        let (d, o, a, c) = await (detailRead, onDutyRead, assignmentsRead, coverageRead)
        detail = Self.merge(d, into: detail)
        onDuty = Self.merge(o, into: onDuty)
        assignments = Self.merge(a, into: assignments)
        coverage = Self.merge(c, into: coverage)
        if let info = detail.value {
            receiver = info.receiver(canManage: receiver.canManage)
            if isAdmin { await loadMembers(teamID: info.teamID) }
        }
    }

    func retry() async {
        detail = .loading
        await load()
    }

    private func loadMembers(teamID: String) async {
        do {
            members = .loaded(try await service.team(teamID).members)
        } catch {
            if members.value == nil { members = .failed }
        }
    }

    /// A sheet wrote the detail (Edit care instructions, Emergency contacts): shown at once.
    func adopt(_ info: CareReceiverInfo) {
        detail = .loaded(info)
    }

    /// Restore (PRD: stays on Care receiver, no longer archived). True once restored.
    func restore() async -> Bool {
        guard isAdmin, isArchived, !isRestoring else { return false }
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }
        do {
            try await service.restoreReceiver(receiver.id)
        } catch {
            restoreError = AppError.from(error).message
            return false
        }
        await load()
        return true
    }

    private static func merge<T: Equatable>(_ result: Result<T, Error>, into part: TeamPart<T>) -> TeamPart<T> {
        switch result {
        case .success(let v): return .loaded(v)
        case .failure: return part.value == nil ? .failed : part
        }
    }

    private nonisolated static func capture<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

/// Archive this care receiver? (PRD): what stops and what stays, then Archive or Cancel.
@MainActor
@Observable
final class ArchiveReceiverModel {
    let receiverID: String
    let name: String
    private(set) var isWorking = false
    private(set) var failure: String?

    private let service: TeamService

    init(receiverID: String, name: String, service: TeamService) {
        self.receiverID = receiverID
        self.name = name
        self.service = service
    }

    /// True once archived; the sheet goes back to Care receiver, now archived.
    func archive() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await service.archiveReceiver(receiverID)
            return true
        } catch {
            failure = AppError.from(error).message
            return false
        }
    }
}

/// What a sheet's Save says when it was refused: the receiver is archived (409), the
/// server's 400 message, or why the call failed.
@MainActor
private func refusal<T>(_ outcome: ReceiverWriteOutcome<T>, name: String) -> String? {
    switch outcome {
    case .done: nil
    case .refused: TeamText.archivedRefusal(name)
    case .rejected(let message): AppError.forStatus(400, serverMessage: message).message
    }
}

/// Edit care receiver (PRD; Figma 451:3634): name and time zone. Changing the zone keeps
/// their routines at their wall-clock times.
@MainActor
@Observable
final class EditCareReceiverModel {
    let receiverID: String
    var name: String
    var zone: TimeZone
    private(set) var isSaving = false
    private(set) var error: String?

    private let original: (name: String, zone: String)
    private let service: TeamService

    init(info: CareReceiverInfo, service: TeamService) {
        receiverID = info.id
        name = info.name
        zone = info.timeZone
        original = (info.name, info.timeZone.identifier)
        self.service = service
    }

    var zones: [TimeZone] { AddCareReceiverModel.zones(including: zone) }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isChanged: Bool { trimmed != original.name || zone.identifier != original.zone }
    var canSave: Bool { !trimmed.isEmpty && trimmed.count <= 100 && !isSaving }

    /// The receiver as saved, or nil with `error` set. Saving nothing changed sends nothing.
    func save() async -> TeamReceiver? {
        guard canSave else { return nil }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let outcome = try await service.changeReceiver(receiverID, trimmed, zone)
            if case .done(let r) = outcome { return r }
            error = refusal(outcome, name: original.name)
            return nil
        } catch {
            self.error = AppError.from(error).message
            return nil
        }
    }
}

/// Edit care instructions (PRD; Figma 451:3655): one free-form document in the admin's own
/// words. Save records who changed it and when; an empty body clears it.
@MainActor
@Observable
final class EditInstructionsModel {
    let receiverID: String
    let name: String
    /// The receiver's, which the stamp's date is read in.
    let zone: TimeZone
    /// Who last changed them, shown under the box.
    let stamp: CareInstructionsInfo?
    var body: String
    private(set) var isSaving = false
    private(set) var error: String?

    static let maxLength = 20_000

    private let service: TeamService

    init(info: CareReceiverInfo, service: TeamService) {
        receiverID = info.id
        name = info.name
        zone = info.timeZone
        stamp = info.instructions
        body = info.instructions?.body ?? ""
        self.service = service
    }

    var isTooLong: Bool { body.count > Self.maxLength }
    var canSave: Bool { !isTooLong && !isSaving }

    /// The receiver with the new instructions, or nil with `error` set.
    func save() async -> CareReceiverInfo? {
        guard canSave else { return nil }
        isSaving = true
        error = nil
        defer { isSaving = false }
        // Blank lines around the words are not part of them; nothing but blanks clears them.
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let outcome = try await service.changeInstructions(receiverID, text)
            if case .done(let info) = outcome { return info }
            error = refusal(outcome, name: name)
            return nil
        } catch {
            self.error = AppError.from(error).message
            return nil
        }
    }
}

/// Emergency contacts (PRD; Figma 451:3670): each a name, a relationship and a phone number,
/// in the order caregivers see them. Add, remove and reorder here; Save sends the whole list.
@MainActor
@Observable
final class EmergencyContactsModel {
    struct Draft: Equatable, Identifiable {
        /// Stable while editing, for a contact not yet saved too.
        let id: UUID
        /// Nil for a contact added here.
        let contactID: String?
        var name: String
        var relationship: String
        var phone: String

        var isBlank: Bool { [name, relationship, phone].allSatisfy { $0.trimmed.isEmpty } }
    }

    static let maxContacts = 20

    let receiverID: String
    let name: String
    var drafts: [Draft]
    private(set) var isSaving = false
    private(set) var error: String?

    private let service: TeamService

    init(info: CareReceiverInfo, service: TeamService) {
        receiverID = info.id
        name = info.name
        drafts = info.contacts.map {
            Draft(id: UUID(), contactID: $0.id, name: $0.name, relationship: $0.relationship, phone: $0.phone)
        }
        self.service = service
    }

    var canAdd: Bool { drafts.count < Self.maxContacts }

    func add() {
        guard canAdd else { return }
        drafts.append(Draft(id: UUID(), contactID: nil, name: "", relationship: "", phone: ""))
    }

    func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    /// Moves `id` to where `target` is — dropped on another contact.
    func move(_ id: UUID, to target: UUID) {
        guard id != target, let from = drafts.firstIndex(where: { $0.id == id }),
              let to = drafts.firstIndex(where: { $0.id == target }) else { return }
        let moving = drafts.remove(at: from)
        drafts.insert(moving, at: to)
    }

    /// One place up (-1) or down (+1), for VoiceOver's actions.
    func move(_ id: UUID, by offset: Int) {
        guard let from = drafts.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard drafts.indices.contains(to) else { return }
        drafts.swapAt(from, to)
    }

    /// A contact added and left blank is dropped rather than refused.
    private var kept: [Draft] { drafts.filter { !$0.isBlank } }

    var problems: [String] {
        var out: [String] = []
        if kept.contains(where: { $0.name.trimmed.isEmpty }) { out.append("Give every contact a name.") }
        if kept.contains(where: { $0.phone.trimmed.isEmpty }) { out.append("Give every contact a phone number.") }
        if kept.contains(where: { $0.name.trimmed.count > 100 || $0.relationship.trimmed.count > 100 }) {
            out.append("Keep names and relationships to 100 characters or fewer.")
        }
        if kept.contains(where: { $0.phone.trimmed.count > 40 }) {
            out.append("Keep phone numbers to 40 characters or fewer.")
        }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving }

    var write: [EmergencyContactWrite] {
        kept.map {
            EmergencyContactWrite(contactID: $0.contactID, name: $0.name.trimmed,
                                  relationship: $0.relationship.trimmed, phone: $0.phone.trimmed)
        }
    }

    /// The receiver with the new list, or nil with `error` set.
    func save() async -> CareReceiverInfo? {
        guard canSave else { return nil }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let outcome = try await service.changeContacts(receiverID, write)
            if case .done(let info) = outcome { return info }
            error = refusal(outcome, name: name)
            return nil
        } catch {
            self.error = AppError.from(error).message
            return nil
        }
    }
}

/// An assignment (PRD "An assignment"; Figma 451:3735): one caregiver, one day, the hours.
/// Saving a different caregiver hands it to them; Remove drops this one, and the rule that
/// made it stays exactly as it was. An end earlier than the start runs past midnight.
@MainActor
@Observable
final class AssignmentModel {
    let receiverID: String
    let receiverName: String
    let zone: TimeZone
    /// Nil for a new one.
    let existing: AssignmentInfo?
    /// Who it can be given to: the team's caregivers now.
    let members: [TeamMemberInfo]
    /// The rule that made it, for the caption.
    let rule: CoverageScheduleInfo?

    var userID: String?
    var day: LocalDay
    private(set) var startTime: String
    private(set) var endTime: String
    /// Days from the start's to the end's: 1 overnight. Kept from an existing assignment
    /// until the hours change.
    private(set) var endDayOffset: Int

    private(set) var isSaving = false
    private(set) var isRemoving = false
    private(set) var error: String?

    private let service: TeamService
    private let clock: @MainActor () -> Date

    init(receiverID: String, receiverName: String, zone: TimeZone, existing: AssignmentInfo?,
         members: [TeamMemberInfo], rule: CoverageScheduleInfo? = nil, service: TeamService,
         clock: @escaping @MainActor () -> Date = Date.init) {
        self.receiverID = receiverID
        self.receiverName = receiverName
        self.zone = zone
        self.existing = existing
        self.members = members
        self.rule = rule
        self.service = service
        self.clock = clock
        if let existing {
            userID = existing.userID
            day = existing.starts.day
            startTime = existing.starts.time
            endTime = existing.ends.time
            endDayOffset = Self.days(from: existing.starts.day, to: existing.ends.day)
        } else {
            // New: nobody chosen yet, today, 8:00 AM to 4:00 PM (Figma 451:3735).
            userID = nil
            day = LocalDay(clock(), zone: zone)
            startTime = "08:00"
            endTime = "16:00"
            endDayOffset = 0
        }
    }

    var isNew: Bool { existing == nil }

    /// The caregiver's name: someone on the team now, or the name it was saved under.
    var caregiverName: String? {
        guard let userID else { return nil }
        return members.first { $0.userID == userID }?.name
            ?? (existing?.userID == userID ? existing?.caregiverName : nil)
    }

    func setStart(_ time: String) {
        startTime = time
        endDayOffset = Self.offset(start: startTime, end: endTime)
    }

    func setEnd(_ time: String) {
        endTime = time
        endDayOffset = Self.offset(start: startTime, end: endTime)
    }

    var starts: LocalDateTime { LocalDateTime(day: day, time: startTime) }
    var ends: LocalDateTime { LocalDateTime(day: day.adding(days: endDayOffset), time: endTime) }

    /// The new caregiver is someone else: Save hands it to them (PRD).
    var isHandOff: Bool { existing != nil && userID != existing?.userID }

    var problems: [String] {
        var out: [String] = []
        if userID == nil {
            out.append("Choose a caregiver.")
        } else if let userID, !members.isEmpty, !members.contains(where: { $0.userID == userID }) {
            out.append("Choose someone on this care team now.")
        }
        if startTime == endTime && endDayOffset == 0 {
            out.append("The end time can’t be the same as the start.")
        }
        if ends <= LocalDateTime(clock(), zone: zone) {
            out.append("That time has already passed.")
        }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving && !isRemoving }

    /// True once saved; the sheet goes back to Care receiver.
    func save() async -> Bool {
        guard canSave, let userID else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let write = AssignmentWrite(userID: userID, starts: starts, ends: ends)
        do {
            let outcome: ReceiverWriteOutcome<AssignmentInfo>
            if let existing {
                outcome = try await service.changeAssignment(existing.id, write)
            } else {
                outcome = try await service.addAssignment(receiverID, write)
            }
            return settle(outcome)
        } catch {
            self.error = AppError.from(error).message
            return false
        }
    }

    /// Remove: this one assignment, and nothing else (PRD). True once removed.
    func remove() async -> Bool {
        guard let existing, !isRemoving, !isSaving else { return false }
        isRemoving = true
        error = nil
        defer { isRemoving = false }
        do {
            return settle(try await service.removeAssignment(existing.id))
        } catch {
            self.error = AppError.from(error).message
            return false
        }
    }

    private func settle<T>(_ outcome: ReceiverWriteOutcome<T>) -> Bool {
        switch outcome {
        case .done: return true
        case .refused:
            // A new one can only be refused for an archived receiver; an existing one may
            // also have ended, and the API doesn't say which.
            error = isNew ? TeamText.archivedRefusal(receiverName) : TeamText.assignmentRefused
        case .rejected(let message):
            error = AppError.forStatus(400, serverMessage: message).message
        }
        return false
    }

    /// 1 when the end is before the start on the clock: it runs past midnight.
    static func offset(start: String, end: String) -> Int {
        guard let s = LocalDateTime.minutes(start), let e = LocalDateTime.minutes(end) else { return 0 }
        return e < s ? 1 : 0
    }

    static func days(from a: LocalDay, to b: LocalDay) -> Int {
        var n = 0
        var d = a
        while d < b, n < 400 {
            d = d.adding(days: 1)
            n += 1
        }
        return n
    }
}

/// A coverage schedule (PRD "A coverage schedule"; Figma 451:3773): a caregiver, the days
/// and the hours, and when it ends, if it ends. Saving an existing one redraws the
/// assignments still ahead except any changed by hand. Remove asks first.
@MainActor
@Observable
final class CoverageScheduleModel {
    let receiverID: String
    let receiverName: String
    let zone: TimeZone
    let existing: CoverageScheduleInfo?
    let members: [TeamMemberInfo]

    var userID: String?
    var days: Set<ScheduleWeekday>
    /// Not offered (Figma shows days only); kept from an existing rule, 1 for a new one.
    let interval: Int
    var startTime: String
    var endTime: String
    var endsOn: LocalDay?
    private let storedEndsOn: LocalDay?

    private(set) var isSaving = false
    private(set) var isRemoving = false
    private(set) var error: String?
    private(set) var removeError: String?

    private let service: TeamService
    private let clock: @MainActor () -> Date

    init(receiverID: String, receiverName: String, zone: TimeZone, existing: CoverageScheduleInfo?,
         members: [TeamMemberInfo], service: TeamService, clock: @escaping @MainActor () -> Date = Date.init) {
        self.receiverID = receiverID
        self.receiverName = receiverName
        self.zone = zone
        self.existing = existing
        self.members = members
        self.service = service
        self.clock = clock
        userID = existing?.userID
        days = Set(existing?.days ?? [])
        interval = existing?.interval ?? 1
        // New: no days yet, 8:00 AM to 4:00 PM, forever (Figma 451:3773).
        startTime = existing?.startTime ?? "08:00"
        endTime = existing?.endTime ?? "16:00"
        endsOn = existing?.endsOn
        storedEndsOn = existing?.endsOn
    }

    var isNew: Bool { existing == nil }
    var today: LocalDay { LocalDay(clock(), zone: zone) }

    var caregiverName: String? {
        guard let userID else { return nil }
        return members.first { $0.userID == userID }?.name
            ?? (existing?.userID == userID ? existing?.caregiverName : nil)
    }

    func toggle(_ day: ScheduleWeekday) {
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
    }

    var problems: [String] {
        var out: [String] = []
        if userID == nil {
            out.append("Choose a caregiver.")
        } else if let userID, !members.isEmpty, !members.contains(where: { $0.userID == userID }) {
            out.append("Choose someone on this care team now.")
        }
        if days.isEmpty { out.append("Choose at least one day.") }
        if startTime == endTime { out.append("The end time can’t be the same as the start.") }
        if let endsOn, endsOn != storedEndsOn, endsOn < today {
            out.append("The end date can’t be before today.")
        }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving && !isRemoving }

    var write: CoverageScheduleWrite? {
        guard let userID else { return nil }
        return CoverageScheduleWrite(userID: userID, days: days.sorted(), interval: interval,
                                     startTime: startTime, endTime: endTime, endsOn: endsOn)
    }

    /// True once saved.
    func save() async -> Bool {
        guard canSave, let write else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let outcome: ReceiverWriteOutcome<CoverageScheduleInfo>
            if let existing {
                outcome = try await service.changeCoverage(existing.id, write)
            } else {
                outcome = try await service.addCoverage(receiverID, write)
            }
            if case .done = outcome { return true }
            error = refusal(outcome, name: receiverName)
            return false
        } catch {
            self.error = AppError.from(error).message
            return false
        }
    }

    /// Remove this coverage schedule?'s Remove: the rule and its assignments still ahead.
    /// True once removed.
    func remove() async -> Bool {
        guard let existing, !isRemoving else { return false }
        isRemoving = true
        removeError = nil
        defer { isRemoving = false }
        do {
            let outcome = try await service.removeCoverage(existing.id)
            if case .done = outcome { return true }
            removeError = refusal(outcome, name: receiverName)
            return false
        } catch {
            removeError = AppError.from(error).message
            return false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
