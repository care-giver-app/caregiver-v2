import Foundation
import Observation

/// What the A field sheet edits (PRD "A field"): a copy of one `FieldDraft`, handed back
/// on Save. The draft's own `fieldID` says whether the tracker already has the field,
/// which fixes its type and its one-or-several answers; options the tracker already has
/// can be renamed and retired but never deleted, while ones added since can be.
@MainActor @Observable
final class FieldEditor {
    static let kinds: [FieldKind] = [.number, .text, .boolean, .choice, .datetime]

    private(set) var draft: FieldDraft
    /// The low and high as typed, so "9." or a stray letter survives until it is fixed.
    var lowText: String
    var highText: String

    init(field: FieldDraft) {
        draft = field
        lowText = Self.format(field.low)
        highText = Self.format(field.high)
    }

    // MARK: Name, required, unit

    var label: String {
        get { draft.label }
        set { draft.label = newValue }
    }

    var unit: String {
        get { draft.unit }
        set { draft.unit = newValue }
    }

    var required: Bool {
        get { draft.required }
        set { draft.required = newValue }
    }

    // MARK: Type

    /// Once the tracker has the field its type is shown but cannot be changed.
    var kindLocked: Bool { draft.exists }

    /// Changes the type, clearing whatever only the old type had. Does nothing on a field
    /// the tracker already has.
    func setKind(_ kind: FieldKind) {
        guard !kindLocked, kind != draft.kind else { return }
        draft.kind = kind
        if kind != .number {
            draft.unit = ""
            draft.alertsOutOfRange = false
            draft.low = nil
            draft.high = nil
            lowText = ""
            highText = ""
        }
        if kind != .choice {
            draft.multiple = false
            draft.options = []
        }
    }

    // MARK: Choice

    /// Whether a choice takes several answers; fixed with the type.
    var multiple: Bool {
        get { draft.multiple }
        set { if !kindLocked { draft.multiple = newValue } }
    }

    var options: [OptionDraft] { draft.options }

    /// Adds a blank option and returns its id, for focusing it.
    @discardableResult
    func addOption() -> OptionDraft.ID {
        let option = OptionDraft(label: "")
        draft.options.append(option)
        return option.id
    }

    func renameOption(_ id: OptionDraft.ID, to label: String) {
        guard let i = index(id) else { return }
        draft.options[i].label = label
    }

    /// Only an option the tracker doesn't have yet can be deleted; the rest are retired.
    func canDelete(_ option: OptionDraft) -> Bool { option.optionID == nil }

    func deleteOption(_ id: OptionDraft.ID) {
        guard let i = index(id), canDelete(draft.options[i]) else { return }
        draft.options.remove(at: i)
    }

    /// Retires or brings back an option the tracker already has.
    func setRetired(_ id: OptionDraft.ID, _ retired: Bool) {
        guard let i = index(id), !canDelete(draft.options[i]) else { return }
        draft.options[i].retired = retired
    }

    private func index(_ id: OptionDraft.ID) -> Int? { draft.options.firstIndex { $0.id == id } }

    // MARK: Range

    var alertsOutOfRange: Bool {
        get { draft.alertsOutOfRange }
        set { if draft.kind == .number { draft.alertsOutOfRange = newValue } }
    }

    var low: Double? { Self.parse(lowText) ?? nil }
    var high: Double? { Self.parse(highText) ?? nil }

    /// What alerts, as the sheet says it under the range bar; nil until a bound is set.
    var rangeSentence: String? {
        let unit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = unit.isEmpty ? "" : " \(unit)"
        switch (low, high) {
        case let (low?, high?):
            return "A reading below \(Self.format(low)) or above \(Self.format(high))\(suffix) alerts the team."
        case let (low?, nil):
            return "A reading below \(Self.format(low))\(suffix) alerts the team."
        case let (nil, high?):
            return "A reading above \(Self.format(high))\(suffix) alerts the team."
        case (nil, nil):
            return nil
        }
    }

    // MARK: Save

    /// The field as it would be saved, with the typed low and high read in.
    var field: FieldDraft {
        var f = draft
        if f.kind == .number && f.alertsOutOfRange {
            f.low = low
            f.high = high
        } else {
            f.low = nil
            f.high = nil
        }
        return f
    }

    /// Everything stopping Save, in the order the sheet shows it.
    var problems: [String] {
        var out = field.problems
        guard draft.kind == .number, draft.alertsOutOfRange else { return out }
        let lowBad = Self.parse(lowText) == nil
        let highBad = Self.parse(highText) == nil
        if lowBad || highBad {
            out.append("Low and high must be numbers.")
        } else if low == nil && high == nil {
            out.append("Set a low, a high, or both.")
        }
        return out
    }

    var canSave: Bool { problems.isEmpty }

    // MARK: Numbers

    /// `.some(nil)` for a blank box, `.some(value)` for a number, `nil` for anything else.
    static func parse(_ text: String) -> Double?? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .some(nil) }
        guard let v = Double(t), v.isFinite else { return nil }
        return .some(v)
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

extension FieldKind {
    /// The chip each type shows as on A field (Figma 374:3472).
    var chipTitle: String {
        switch self {
        case .number: "Number"
        case .text: "Text"
        case .boolean: "Yes / No"
        case .choice: "Choice"
        case .datetime: "Date & time"
        }
    }
}
