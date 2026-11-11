import Foundation

/// An entry's field values as a caregiver is entering them — Quick log's steps, and Edit
/// entry's fields — with the checks the server makes on them (`ValidateEntryValues`):
/// each value of its field's kind, text and notes within length, choices naming active
/// options, and, when logging, every required active field answered. A number outside
/// its range is not refused; it is recorded and alerts.
struct EntryValuesDraft: Equatable, Sendable {
    static let maxText = 2000
    static let maxNote = 2000

    /// By field id. A field left out is unanswered.
    private(set) var values: [String: EntryValue]
    /// Number fields' text as typed, by field id; parsed into `values`.
    private(set) var numberText: [String: String] = [:]

    init(_ values: [String: EntryValue] = [:]) {
        self.values = values
        for (id, value) in values {
            if case .number(let n) = value { numberText[id] = TrackerText.number(n) }
        }
    }

    // MARK: Entering

    func numberText(for fieldID: String) -> String { numberText[fieldID] ?? "" }

    mutating func setNumberText(_ text: String, for fieldID: String) {
        numberText[fieldID] = text
        values[fieldID] = Self.number(text.trimmingCharacters(in: .whitespaces)).map(EntryValue.number)
    }

    func text(for fieldID: String) -> String {
        if case .string(let s) = values[fieldID] { return s }
        return ""
    }

    mutating func setText(_ text: String, for fieldID: String) {
        values[fieldID] = text.isEmpty ? nil : .string(text)
    }

    func bool(for fieldID: String) -> Bool? {
        if case .bool(let b) = values[fieldID] { return b }
        return nil
    }

    /// Yes or No; choosing the one already chosen leaves it unanswered again.
    mutating func setBool(_ value: Bool, for fieldID: String) {
        values[fieldID] = bool(for: fieldID) == value ? nil : .bool(value)
    }

    func chosen(for fieldID: String) -> [String] {
        if case .list(let ids) = values[fieldID] { return ids }
        return []
    }

    /// A choice chip: one answer replaces, several toggle; choosing the only one clears it.
    mutating func choose(_ optionID: String, in field: TrackerFieldInfo) {
        var ids = chosen(for: field.id)
        if let i = ids.firstIndex(of: optionID) {
            ids.remove(at: i)
        } else if field.multiple {
            ids.append(optionID)
        } else {
            ids = [optionID]
        }
        values[field.id] = ids.isEmpty ? nil : .list(ids)
    }

    func date(for fieldID: String) -> Date? {
        if case .string(let s) = values[fieldID] { return Self.parseISO(s) }
        return nil
    }

    /// A date and time, sent as RFC 3339 with the receiver's offset.
    mutating func setDate(_ date: Date?, for fieldID: String, zone: TimeZone) {
        guard let date else {
            values[fieldID] = nil
            return
        }
        let f = ISO8601DateFormatter()
        f.timeZone = zone
        f.formatOptions = [.withInternetDateTime]
        values[fieldID] = .string(f.string(from: date))
    }

    // MARK: Checking and sending

    /// What stops these values being sent for a tracker with `fields`. `requireAll` is
    /// logging care: every required active field must be answered. Planning and skipping
    /// require nothing.
    func problems(for fields: [TrackerFieldInfo], requireAll: Bool) -> [String] {
        var out: [String] = []
        for field in fields where !field.paused {
            let typed = numberText(for: field.id).trimmingCharacters(in: .whitespaces)
            if field.kind == .number, !typed.isEmpty, Self.number(typed) == nil {
                out.append("\(field.label): enter a number.")
                continue
            }
            if field.kind == .text, text(for: field.id).count > Self.maxText {
                out.append("\(field.label): keep it to \(Self.maxText) characters or fewer.")
                continue
            }
            if requireAll, field.required, sent(for: [field])[field.id] == nil {
                out.append("\(field.label) is required.")
            }
        }
        return out
    }

    /// The values to send for a tracker with `fields`: active fields only, each of its
    /// field's kind, text trimmed, blanks left out, and a choice kept to active options
    /// (one, unless the field takes several). A pre-filled value for a field paused or an
    /// option retired since is dropped, as the server would refuse it.
    func sent(for fields: [TrackerFieldInfo]) -> [String: EntryValue] {
        var out: [String: EntryValue] = [:]
        for field in fields where !field.paused {
            guard let value = values[field.id] else { continue }
            switch (field.kind, value) {
            case (.number, .number(let n)) where n.isFinite:
                out[field.id] = value
            case (.boolean, .bool):
                out[field.id] = value
            case (.text, .string(let s)):
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out[field.id] = .string(t) }
            case (.datetime, .string(let s)):
                if Self.parseISO(s) != nil { out[field.id] = value }
            case (.choice, .list(let ids)):
                let active = Set(field.options.filter { !$0.retired }.map(\.id))
                var seen = Set<String>()
                var kept = ids.filter { active.contains($0) && seen.insert($0).inserted }
                if !field.multiple { kept = Array(kept.prefix(1)) }
                if !kept.isEmpty { out[field.id] = .list(kept) }
            default:
                break
            }
        }
        return out
    }

    /// A typed number, or nil when it isn't one: "inf", "nan" and "1e999" are refused.
    static func number(_ text: String) -> Double? {
        guard let n = Double(text), n.isFinite else { return nil }
        return n
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
