import Foundation

// What Add tracker, Edit tracker, A field and A schedule hold while an admin edits,
// before anything is sent. Each draft says what is wrong with it in words a caregiver
// can act on (`problems`), mirroring the contract's limits so a Save the server would
// refuse is caught first, and turns into the write the service sends.

/// One answer a choice offers.
struct OptionDraft: Equatable, Identifiable, Sendable {
    /// Local identity for lists; never sent.
    let id = UUID()
    /// Nil until the tracker it belongs to has been saved with it.
    var optionID: String?
    var label: String
    /// Retired options stay on the field (existing ones are never deleted) but are no
    /// longer offered.
    var retired: Bool = false

    init(optionID: String? = nil, label: String, retired: Bool = false) {
        self.optionID = optionID
        self.label = label
        self.retired = retired
    }

    var write: OptionWrite {
        OptionWrite(optionID: optionID, label: label.trimmed, retired: retired)
    }
}

/// One field of a tracker being added or edited.
struct FieldDraft: Equatable, Identifiable, Sendable {
    static let maxLabel = 100
    static let maxUnit = 20

    let id = UUID()
    /// Nil for a field the tracker doesn't have yet. Once set, the field's kind and
    /// single/multiple answer are fixed.
    var fieldID: String?
    var label: String
    var kind: FieldKind
    /// Numbers only.
    var unit: String = ""
    var required: Bool = false
    var paused: Bool = false
    /// Numbers only: "Alert when out of range". Off sends no range at all.
    var alertsOutOfRange: Bool = false
    var low: Double?
    var high: Double?
    /// Choices only.
    var multiple: Bool = false
    var options: [OptionDraft] = []

    init(fieldID: String? = nil, label: String, kind: FieldKind, unit: String = "",
         required: Bool = false, paused: Bool = false, alertsOutOfRange: Bool = false,
         low: Double? = nil, high: Double? = nil, multiple: Bool = false, options: [OptionDraft] = []) {
        self.fieldID = fieldID
        self.label = label
        self.kind = kind
        self.unit = unit
        self.required = required
        self.paused = paused
        self.alertsOutOfRange = alertsOutOfRange
        self.low = low
        self.high = high
        self.multiple = multiple
        self.options = options
    }

    /// A field as a template or an earlier write carries it.
    init(_ w: FieldWrite) {
        self.init(fieldID: w.fieldID, label: w.label, kind: w.kind, unit: w.unit ?? "",
                  required: w.required, paused: w.paused,
                  alertsOutOfRange: w.range.map { $0.low != nil || $0.high != nil } ?? false,
                  low: w.range?.low, high: w.range?.high, multiple: w.multiple,
                  options: w.options.map { OptionDraft(optionID: $0.optionID, label: $0.label, retired: $0.retired) })
    }

    /// A field the tracker already has.
    init(_ f: TrackerFieldInfo) {
        self.init(fieldID: f.id, label: f.label, kind: f.kind, unit: f.unit ?? "",
                  required: f.required, paused: f.paused,
                  alertsOutOfRange: f.range.map { $0.low != nil || $0.high != nil } ?? false,
                  low: f.range?.low, high: f.range?.high, multiple: f.multiple,
                  options: f.options.map { OptionDraft(optionID: $0.id, label: $0.label, retired: $0.retired) })
    }

    /// Whether the tracker already has this field, which locks its kind and answers.
    var exists: Bool { fieldID != nil }

    var activeOptions: [OptionDraft] { options.filter { !$0.retired } }

    /// Everything wrong with this field, in the order the sheet shows it.
    var problems: [String] {
        var out: [String] = []
        let name = label.trimmed
        if name.isEmpty {
            out.append("Give the field a name.")
        } else if name.count > Self.maxLabel {
            out.append("Keep the field's name to \(Self.maxLabel) characters or fewer.")
        }
        switch kind {
        case .number:
            if unit.trimmed.count > Self.maxUnit {
                out.append("Keep the unit to \(Self.maxUnit) characters or fewer.")
            }
            if alertsOutOfRange, let low, let high, low > high {
                out.append("The low end can't be above the high end.")
            }
        case .choice:
            if options.contains(where: { $0.label.trimmed.isEmpty }) {
                out.append("Give every option a name.")
            } else if options.contains(where: { $0.label.trimmed.count > Self.maxLabel }) {
                out.append("Keep each option to \(Self.maxLabel) characters or fewer.")
            }
            if activeOptions.isEmpty {
                out.append("Add at least one option.")
            }
        case .text, .boolean, .datetime:
            break
        }
        return out
    }

    var write: FieldWrite {
        let range: ValueRangeInfo? = (kind == .number && alertsOutOfRange && (low != nil || high != nil))
            ? ValueRangeInfo(low: low, high: high) : nil
        let unit = self.unit.trimmed
        return FieldWrite(
            fieldID: fieldID, label: label.trimmed, kind: kind,
            unit: kind == .number && !unit.isEmpty ? unit : nil,
            required: required, paused: paused, range: range,
            multiple: kind == .choice && multiple,
            options: kind == .choice ? options.map(\.write) : []
        )
    }
}

/// Add tracker's or Edit tracker's name, icon, color, fields and gap.
struct TrackerDraft: Equatable, Sendable {
    static let maxName = 100

    var name: String
    /// An SF Symbol name.
    var icon: String
    /// `#RRGGBB`.
    var color: String
    var fields: [FieldDraft]
    /// Nil: no gap watches the tracker.
    var gapHours: Int?

    init(name: String, icon: String, color: String, fields: [FieldDraft] = [], gapHours: Int? = nil) {
        self.name = name
        self.icon = icon
        self.color = color
        self.fields = fields
        self.gapHours = gapHours
    }

    /// Start from scratch: no name, no fields, no gap. `icon` and `color` are whatever
    /// the sheet starts its pickers on.
    static func scratch(icon: String, color: String) -> TrackerDraft {
        TrackerDraft(name: "", icon: icon, color: color)
    }

    init(_ template: TrackerTemplate) {
        self.init(name: template.name, icon: template.icon, color: template.color,
                  fields: template.fields.map(FieldDraft.init), gapHours: template.gapHours)
    }

    /// Edit tracker, opened on a tracker as it is now: every field, paused ones included.
    init(_ profile: TrackerProfile) {
        self.init(name: profile.name, icon: profile.icon, color: profile.color,
                  fields: profile.fields.map(FieldDraft.init), gapHours: profile.gapHours)
    }

    var problems: [String] {
        var out: [String] = []
        let name = self.name.trimmed
        if name.isEmpty {
            out.append("Give the tracker a name.")
        } else if name.count > Self.maxName {
            out.append("Keep the name to \(Self.maxName) characters or fewer.")
        }
        if icon.trimmed.isEmpty {
            out.append("Choose an icon.")
        }
        if !Self.isHexColor(color) {
            out.append("Choose a color.")
        }
        for field in fields {
            let title = field.label.trimmed.isEmpty ? "A field" : field.label.trimmed
            out += field.problems.map { "\(title): \($0)" }
        }
        if let gapHours, gapHours < 1 {
            out.append("A gap must be at least 1 hour.")
        }
        return out
    }

    var write: TrackerWrite {
        TrackerWrite(name: name.trimmed, icon: icon, color: color, fields: fields.map(\.write), gapHours: gapHours)
    }

    static func isHexColor(_ s: String) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy(\.isHexDigit)
    }
}

/// A schedule being added or changed on A schedule.
struct ScheduleDraft: Equatable, Sendable {
    static let maxLabel = 100
    /// Every week, two weeks, month and two months (PRD "A schedule"; ADR 0012).
    static let intervals = [1, 2, 4, 8]

    /// Nil for a schedule not saved yet.
    var scheduleID: String?
    /// Blank lets the server derive a name.
    var label: String
    var days: Set<ScheduleWeekday>
    /// In weeks; one of `intervals`.
    var interval: Int
    /// Local `HH:MM` in the receiver's time zone.
    var time: String
    var endsOn: LocalDay?
    /// Pre-filled values by field id. A field left out is left for whoever logs it.
    var plannedValues: [String: EntryValue]
    var unrecordedAlert: Bool
    /// The end date the schedule was saved with, which may be past by now and may be
    /// saved again as it is.
    private(set) var storedEndsOn: LocalDay?

    init(scheduleID: String? = nil, label: String = "", days: Set<ScheduleWeekday> = [], interval: Int = 1,
         time: String = "08:00", endsOn: LocalDay? = nil, plannedValues: [String: EntryValue] = [:],
         unrecordedAlert: Bool = false) {
        self.scheduleID = scheduleID
        self.label = label
        self.days = days
        self.interval = interval
        self.time = time
        self.endsOn = endsOn
        self.plannedValues = plannedValues
        self.unrecordedAlert = unrecordedAlert
        self.storedEndsOn = scheduleID == nil ? nil : endsOn
    }

    init(_ s: TrackerScheduleItem) {
        self.init(scheduleID: s.id, label: s.label ?? "", days: Set(s.days), interval: s.interval,
                  time: s.time, endsOn: s.endsOn, plannedValues: s.plannedValues,
                  unrecordedAlert: s.unrecordedAlert)
    }

    /// `today` is the receiver's local date: an end date before it is refused, unless it
    /// is the one the schedule already has.
    func problems(today: LocalDay) -> [String] {
        var out: [String] = []
        if label.trimmed.count > Self.maxLabel {
            out.append("Keep the label to \(Self.maxLabel) characters or fewer.")
        }
        if days.isEmpty {
            out.append("Choose at least one day.")
        }
        if !Self.intervals.contains(interval) {
            out.append("Choose how often it repeats.")
        }
        if !Self.isTime(time) {
            out.append("Choose a time.")
        }
        if let endsOn, endsOn != storedEndsOn, endsOn < today {
            out.append("The end date can't be before today.")
        }
        return out
    }

    /// The write for a tracker with `fields`. Pre-filled values keep only the tracker's
    /// active fields, with a value of the field's kind; a blank value, and any retired
    /// option, is left out.
    func write(for fields: [TrackerFieldInfo]) -> ScheduleWrite {
        var planned: [String: EntryValue] = [:]
        for field in fields where !field.paused {
            guard let value = plannedValues[field.id] else { continue }
            switch (field.kind, value) {
            case (.number, .number), (.boolean, .bool):
                planned[field.id] = value
            case (.text, .string(let s)), (.datetime, .string(let s)):
                if !s.trimmed.isEmpty { planned[field.id] = .string(field.kind == .text ? s.trimmed : s) }
            case (.choice, .list(let ids)):
                let active = Set(field.options.filter { !$0.retired }.map(\.id))
                var seen = Set<String>()
                var kept = ids.filter { active.contains($0) && seen.insert($0).inserted }
                if !field.multiple { kept = Array(kept.prefix(1)) }
                if !kept.isEmpty { planned[field.id] = .list(kept) }
            default:
                break
            }
        }
        let label = self.label.trimmed
        return ScheduleWrite(label: label.isEmpty ? nil : label, days: days.sorted(), interval: interval,
                             time: time, endsOn: endsOn, plannedValues: planned, unrecordedAlert: unrecordedAlert)
    }

    static func isTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
