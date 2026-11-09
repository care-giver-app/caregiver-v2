import Foundation

/// A schedule (PRD "A schedule") and Remove this schedule?: one recurring rule on a
/// tracker and the values it pre-fills, written the moment it is saved or its removal
/// confirmed — not on Edit tracker's Save. Admins only.
@MainActor
@Observable
final class ScheduleSheetModel {
    /// How the sheet ended, for Edit tracker, which reloads its schedules either way.
    enum Outcome: Equatable {
        /// Saved. `replacedGap`: the tracker's gap was turned off to make room for it.
        case saved(TrackerScheduleItem, replacedGap: Bool)
        case removed
    }

    var draft: ScheduleDraft
    /// Number fields' text as typed, by field id; parsed into `draft.plannedValues`.
    private(set) var numberText: [String: String] = [:]

    private(set) var isSaving = false
    private(set) var saveFailed: AppError?
    /// The server said the tracker has a gap this schedule would turn off; the sheet asks
    /// before resending.
    var confirmingGap = false

    private(set) var isRemoving = false
    private(set) var removeFailed: AppError?

    let trackerID: String
    let trackerName: String
    let trackerIcon: String
    let trackerColor: String
    let receiver: TeamReceiver
    /// The schedule being changed; nil for a new one.
    let existing: TrackerScheduleItem?
    /// The fields that take a pre-filled value: active ones, in the tracker's order.
    let fields: [TrackerFieldInfo]
    private let allFields: [TrackerFieldInfo]
    /// Set for a new schedule on a tracker a gap watches and that has no schedules yet:
    /// the sheet says up front that saving turns the gap off, and Save sends `replaceGap`.
    let replacesGap: Bool
    /// The gap being replaced, in hours, when known.
    let gapHours: Int?
    private let service: TrackersService
    private let now: () -> Date

    init(trackerID: String, trackerName: String, trackerIcon: String, trackerColor: String,
         fields: [TrackerFieldInfo], receiver: TeamReceiver, existing: TrackerScheduleItem?,
         replacesGap: Bool = false, gapHours: Int? = nil,
         service: TrackersService, now: @escaping () -> Date = Date.init) {
        self.trackerID = trackerID
        self.trackerName = trackerName
        self.trackerIcon = trackerIcon
        self.trackerColor = trackerColor
        self.allFields = fields
        self.fields = fields.filter { !$0.paused }
        self.receiver = receiver
        self.existing = existing
        self.replacesGap = existing == nil && replacesGap
        self.gapHours = gapHours
        self.service = service
        self.now = now
        if let existing {
            draft = ScheduleDraft(existing)
        } else {
            // New: no days yet, every week, 8:00 AM, never ends, alert on (Figma 375:3600).
            draft = ScheduleDraft(unrecordedAlert: true)
        }
        for field in fields where field.kind == .number {
            if case .number(let n) = draft.plannedValues[field.id] {
                numberText[field.id] = TrackerText.number(n)
            }
        }
    }

    /// From Edit tracker: its fields as saved (pre-filled values are checked against
    /// those) and whether a gap is saved on the server. An unsaved gap switch doesn't
    /// count — this sheet writes at once, against the tracker as saved.
    convenience init(editing model: EditTrackerV1Model, target: EditTrackerV1Sheet.ScheduleTarget) {
        let existing: TrackerScheduleItem?
        if case .existing(let s) = target { existing = s } else { existing = nil }
        self.init(trackerID: model.profile.id, trackerName: model.draft.name.isEmpty ? model.profile.name : model.draft.name,
                  trackerIcon: model.draft.icon, trackerColor: model.draft.color,
                  fields: model.profile.fields, receiver: model.receiver, existing: existing,
                  replacesGap: model.newScheduleReplacesGap, gapHours: model.savedGapHours,
                  service: model.service)
    }

    var isNew: Bool { existing == nil }

    /// The receiver's date today; an end date before it is refused.
    var today: LocalDay { LocalDay(now(), zone: receiver.timeZone) }

    // MARK: What it is called

    /// What the server will call it if the label is left blank; nil before a day is chosen.
    var derivedName: String? {
        TrackerText.derivedScheduleName(days: Array(draft.days), interval: draft.interval, time: draft.time)
    }

    /// The name Remove this schedule? asks about.
    var displayName: String {
        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        return existing?.name ?? derivedName ?? "this schedule"
    }

    // MARK: Days

    func toggle(_ day: ScheduleWeekday) {
        if draft.days.contains(day) { draft.days.remove(day) } else { draft.days.insert(day) }
    }

    // MARK: Pre-filled values

    func setNumberText(_ text: String, for fieldID: String) {
        numberText[fieldID] = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let n = Self.number(trimmed) {
            draft.plannedValues[fieldID] = .number(n)
        } else {
            draft.plannedValues[fieldID] = nil
        }
    }

    /// A typed number, or nil when it isn't one: "inf", "nan" and "1e999" are refused,
    /// as FieldEditor refuses them.
    private static func number(_ text: String) -> Double? {
        guard let n = Double(text), n.isFinite else { return nil }
        return n
    }

    func text(for fieldID: String) -> String {
        if case .string(let s) = draft.plannedValues[fieldID] { return s }
        return ""
    }

    func setText(_ text: String, for fieldID: String) {
        draft.plannedValues[fieldID] = text.isEmpty ? nil : .string(text)
    }

    func bool(for fieldID: String) -> Bool? {
        if case .bool(let b) = draft.plannedValues[fieldID] { return b }
        return nil
    }

    /// Yes or No; choosing the one already chosen leaves it blank again.
    func setBool(_ value: Bool, for fieldID: String) {
        draft.plannedValues[fieldID] = bool(for: fieldID) == value ? nil : .bool(value)
    }

    func chosen(for fieldID: String) -> [String] {
        if case .list(let ids) = draft.plannedValues[fieldID] { return ids }
        return []
    }

    /// A choice chip: one answer replaces, several toggle; choosing the only one clears it.
    func choose(_ optionID: String, in field: TrackerFieldInfo) {
        var ids = chosen(for: field.id)
        if let i = ids.firstIndex(of: optionID) {
            ids.remove(at: i)
        } else if field.multiple {
            ids.append(optionID)
        } else {
            ids = [optionID]
        }
        draft.plannedValues[field.id] = ids.isEmpty ? nil : .list(ids)
    }

    func date(for fieldID: String) -> Date? {
        if case .string(let s) = draft.plannedValues[fieldID] { return Self.parseISO(s) }
        return nil
    }

    /// A date and time, sent as RFC 3339 with the receiver's offset.
    func setDate(_ date: Date?, for fieldID: String) {
        guard let date else {
            draft.plannedValues[fieldID] = nil
            return
        }
        let f = ISO8601DateFormatter()
        f.timeZone = receiver.timeZone
        f.formatOptions = [.withInternetDateTime]
        draft.plannedValues[fieldID] = .string(f.string(from: date))
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    // MARK: Save

    var problems: [String] {
        var out = draft.problems(today: today)
        for field in fields where field.kind == .number {
            let typed = (numberText[field.id] ?? "").trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty, Self.number(typed) == nil {
                out.append("\(field.label): enter a number, or leave it blank.")
            }
        }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving && !isRemoving }

    var write: ScheduleWrite { draft.write(for: allFields) }

    /// Save. Returns how it ended once written; nil when it can't be sent, failed, or the
    /// admin must first confirm the gap goes (`confirmingGap` set).
    func save() async -> Outcome? {
        guard canSave else { return nil }
        if let existing {
            isSaving = true
            saveFailed = nil
            defer { isSaving = false }
            do {
                return .saved(try await service.changeSchedule(existing.id, write), replacedGap: false)
            } catch {
                saveFailed = AppError.from(error)
                return nil
            }
        }
        return await add(replaceGap: replacesGap)
    }

    /// The admin confirmed the gap may go.
    func confirmReplaceGap() async -> Outcome? {
        confirmingGap = false
        guard canSave else { return nil }
        return await add(replaceGap: true)
    }

    private func add(replaceGap: Bool) async -> Outcome? {
        isSaving = true
        saveFailed = nil
        defer { isSaving = false }
        do {
            let saved = try await service.addSchedule(trackerID, write, replaceGap)
            return .saved(saved, replacedGap: replaceGap)
        } catch is SchedulesOrGapConflict where !replaceGap {
            confirmingGap = true
            return nil
        } catch {
            saveFailed = AppError.from(error)
            return nil
        }
    }

    // MARK: Remove

    /// Remove this schedule?'s Remove. True once removed.
    func remove() async -> Bool {
        guard let existing, !isRemoving else { return false }
        isRemoving = true
        removeFailed = nil
        defer { isRemoving = false }
        do {
            try await service.removeSchedule(existing.id)
            return true
        } catch {
            removeFailed = AppError.from(error)
            return false
        }
    }
}
