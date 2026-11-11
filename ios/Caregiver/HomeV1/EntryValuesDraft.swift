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
    /// The decimal separator `.decimalPad` types in this locale — "," in much of Europe.
    /// Typed numbers take it or "."; numbers shown back use it.
    private let decimalSeparator: String

    init(_ values: [String: EntryValue] = [:], locale: Locale = .current) {
        self.values = values
        decimalSeparator = locale.decimalSeparator ?? "."
        for (id, value) in values {
            if case .number(let n) = value { numberText[id] = Self.shown(n, separator: decimalSeparator) }
        }
    }

    // MARK: Entering

    func numberText(for fieldID: String) -> String { numberText[fieldID] ?? "" }

    mutating func setNumberText(_ text: String, for fieldID: String) {
        numberText[fieldID] = text
        values[fieldID] = Self.number(text.trimmingCharacters(in: .whitespaces), separator: decimalSeparator)
            .map(EntryValue.number)
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
        values[fieldID] = .string(Self.iso(date, zone: zone))
    }

    // MARK: Checking and sending

    /// What stops these values being sent for a tracker with `fields`. `requireAll` is
    /// logging care: every required active field must be answered. Planning and skipping
    /// require nothing.
    func problems(for fields: [TrackerFieldInfo], requireAll: Bool) -> [String] {
        problems(for: fields) { _ in requireAll }
    }

    /// What stops these values being sent, with `requiring` saying which required active
    /// fields must be answered — Edit entry's own rule — and `prior` the entry's values
    /// before this edit, whose retired options still count as answers.
    func problems(for fields: [TrackerFieldInfo], keeping prior: [String: EntryValue] = [:],
                  requiring: (TrackerFieldInfo) -> Bool) -> [String] {
        var out: [String] = []
        for field in fields where !field.paused {
            let typed = numberText(for: field.id).trimmingCharacters(in: .whitespaces)
            if field.kind == .number, !typed.isEmpty, Self.number(typed, separator: decimalSeparator) == nil {
                out.append("\(field.label): enter a number.")
                continue
            }
            if field.kind == .text, text(for: field.id).count > Self.maxText {
                out.append("\(field.label): keep it to \(Self.maxText) characters or fewer.")
                continue
            }
            if field.required, requiring(field), sent(for: [field], keeping: prior)[field.id] == nil {
                out.append("\(field.label) is required.")
            }
        }
        return out
    }

    /// The values to send for a tracker with `fields`: active fields only, each of its
    /// field's kind, text trimmed, blanks left out, and a choice kept to active options
    /// (one, unless the field takes several). A pre-filled value for a field paused or an
    /// option retired since is dropped, as the server would refuse it.
    ///
    /// `prior` is an edited entry's values before the edit: what it already holds for a
    /// field paused since is kept as it was, and options retired since that it already
    /// chose stay chosen, as the server allows — an edit corrects what it touches and
    /// leaves the rest alone.
    func sent(for fields: [TrackerFieldInfo], keeping prior: [String: EntryValue] = [:]) -> [String: EntryValue] {
        var out: [String: EntryValue] = [:]
        for field in fields {
            if field.paused {
                if let held = prior[field.id] { out[field.id] = held }
                continue
            }
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
                var active = Set(field.options.filter { !$0.retired }.map(\.id))
                if case .list(let held) = prior[field.id] { active.formUnion(held) }
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
    /// "." is always a decimal point; so is `separator`, the locale's own.
    static func number(_ text: String, separator: String = ".") -> Double? {
        var t = text
        if separator != ".", !separator.isEmpty, t.contains(separator) {
            guard !t.contains(".") else { return nil }
            t = t.replacingOccurrences(of: separator, with: ".")
        }
        guard let n = Double(t), n.isFinite else { return nil }
        return n
    }

    /// A number as it is shown back for editing, with the locale's decimal separator.
    private static func shown(_ n: Double, separator: String) -> String {
        let s = TrackerText.number(n)
        return separator == "." ? s : s.replacingOccurrences(of: ".", with: separator)
    }

    // Read on every render, so made once. ISO8601DateFormatter is safe to share for parsing.
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        isoPlain.date(from: s) ?? isoFractional.date(from: s)
    }

    private static func iso(_ date: Date, zone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = zone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
