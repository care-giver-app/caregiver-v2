import Foundation

/// Every sentence the Trackers screens print, as pure functions of their inputs.
/// Times are always read in the care receiver's zone, never the device's (PRD
/// "Care receiver"), and `now` is passed in so nothing here depends on the clock.
enum TrackerText {
    // MARK: Trackers list

    /// "Logged 2h ago", or "Never logged" — a different fact, and the one a gap counts from.
    static func recency(lastLoggedAt: Date?, now: Date, zone: TimeZone) -> String {
        guard let last = lastLoggedAt else { return "Never logged" }
        let seconds = max(0, now.timeIntervalSince(last))
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        switch true {
        case minutes < 1: return "Logged just now"
        case hours < 1: return "Logged \(minutes)m ago"
        case days < 1: return "Logged \(hours)h ago"
        case days < 14: return "Logged \(days)d ago"
        default: return "Logged \(shortDate(last, now: now, zone: zone))"
        }
    }

    /// "Paused Nov 3" — said in place of recency, which stopped meaning anything.
    static func paused(at pausedAt: Date?, now: Date, zone: TimeZone) -> String {
        guard let pausedAt else { return "Paused" }
        return "Paused \(shortDate(pausedAt, now: now, zone: zone))"
    }

    /// What a row says under the tracker's name.
    static func rowSubtitle(_ tracker: TrackerItem, now: Date, zone: TimeZone) -> String {
        tracker.status == .paused
            ? paused(at: tracker.pausedAt, now: now, zone: zone)
            : recency(lastLoggedAt: tracker.lastLoggedAt, now: now, zone: zone)
    }

    // MARK: Tracker detail

    /// "2 schedules".
    static func scheduleCount(_ count: Int) -> String {
        count == 1 ? "1 schedule" : "\(count) schedules"
    }

    /// "Alerts after 3 days without an entry" (Figma 428:3752).
    static func gapLine(hours: Int) -> String {
        "Alerts after \(duration(hours: hours)) without an entry"
    }

    /// One sentence per thing wrong right now.
    static func attention(_ item: TrackerAttentionItem, fields: [TrackerFieldInfo],
                          now: Date, zone: TimeZone) -> String {
        switch item {
        case .unrecorded(let at):
            return "The care due \(when(at, now: now, zone: zone, capitalized: false)) went unrecorded."
        case .outOfRange(let fieldID, let value, let range):
            let field = fields.first { $0.id == fieldID }
            let label = field?.label ?? "A reading"
            let unit = field?.unit
            let reading = withUnit(number(value), unit)
            switch (range.low, range.high) {
            case let (low?, high?):
                return "\(label) was \(reading), outside \(number(low))–\(withUnit(number(high), unit))."
            case let (nil, high?):
                return "\(label) was \(reading), above \(withUnit(number(high), unit))."
            case let (low?, nil):
                return "\(label) was \(reading), below \(withUnit(number(low), unit))."
            case (nil, nil):
                return "\(label) was \(reading), outside its range."
            }
        case .gap(let since, let gapHours):
            let elapsed = Int(max(0, now.timeIntervalSince(since)) / 3600)
            // Days once it is past two of them; hours before, where days would round to nothing.
            let gone = elapsed >= 48 ? plural(elapsed / 24, "day") : plural(elapsed, "hour")
            return "Nothing logged in \(gone). The team allows \(duration(hours: gapHours)) without an entry."
        }
    }

    /// Under "Nothing logged yet" when a gap watches it (Figma 371:3397).
    static func neverLoggedGap(hours: Int) -> String {
        let length = hours >= 24 && hours % 24 == 0 ? "\(hours / 24)-day" : "\(hours)-hour"
        return "Its \(length) gap counts from the day it was made."
    }

    /// "Paused Nov 3" headline and what it means (Figma 424:3832).
    static let pausedExplanation = "Nothing new can be logged, and its alerts are off. Its history is kept."

    // MARK: Entries

    /// "Today at 8:04 PM", "Yesterday at 8:02 PM", "Monday at 8:05 PM", "Nov 3 at 9:15 AM".
    static func when(_ date: Date, now: Date, zone: TimeZone, capitalized: Bool = true) -> String {
        let calendar = calendar(zone)
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let time = format(date, "h:mm a", zone)
        let dayText: String
        switch daysAgo {
        case 0: dayText = capitalized ? "Today" : "today"
        case 1: dayText = capitalized ? "Yesterday" : "yesterday"
        case 2...6: dayText = format(date, "EEEE", zone)
        default: dayText = shortDate(date, now: now, zone: zone)
        }
        return "\(dayText) at \(time)"
    }

    static func stateLabel(_ state: EntryState) -> String {
        switch state {
        case .logged: "Logged"
        case .skipped: "Skipped"
        case .unrecorded: "Unrecorded"
        case .scheduled: "Scheduled"
        }
    }

    /// "Logged by Trevor" / "Skipped by Trevor" / "Nothing was recorded".
    static func byline(_ entry: TrackerEntry) -> String? {
        switch entry.state {
        case .logged: entry.byName.map { "Logged by \($0)" }
        case .skipped: entry.byName.map { "Skipped by \($0)" }
        case .unrecorded: "Nothing was recorded"
        case .scheduled: nil
        }
    }

    /// One (label, value) per field the entry carries, in the tracker's field order.
    static func valueRows(_ entry: TrackerEntry, fields: [TrackerFieldInfo],
                          now: Date, zone: TimeZone) -> [(label: String, value: String)] {
        fields.compactMap { field in
            guard let raw = entry.values[field.id],
                  let text = value(raw, field: field, now: now, zone: zone)
            else { return nil }
            return (field.label, text)
        }
    }

    /// One stored value, read by its field: a number with its unit, a choice as its
    /// option labels (retired ones included — the entry still chose it), Yes/No, a
    /// date and time in the receiver's zone, or the text as typed.
    static func value(_ raw: EntryValue, field: TrackerFieldInfo, now: Date, zone: TimeZone) -> String? {
        switch (field.kind, raw) {
        case (.number, .number(let n)):
            return withUnit(number(n), field.unit)
        case (.boolean, .bool(let b)):
            return b ? "Yes" : "No"
        case (.choice, .list(let ids)):
            let labels = ids.compactMap { id in field.options.first { $0.id == id }?.label }
            return labels.isEmpty ? nil : labels.joined(separator: ", ")
        case (.choice, .string(let id)):
            return field.options.first { $0.id == id }?.label
        case (.datetime, .string(let iso)):
            guard let date = parseISO(iso) else { return iso }
            let calendar = calendar(zone)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return format(date, sameYear ? "MMM d 'at' h:mm a" : "MMM d, yyyy 'at' h:mm a", zone)
        case (.text, .string(let s)):
            return s
        default:
            return nil
        }
    }

    // MARK: Schedules

    /// "every week", "every 2 weeks", "every month" (4 weeks), "every two months" (8 weeks).
    static func frequency(intervalWeeks n: Int) -> String {
        switch n {
        case 1: "every week"
        case 4: "every month"
        case 8: "every two months"
        default: "every \(n) weeks"
        }
    }

    /// "Mon, Wed, Fri"; "Every day" when it falls on all seven.
    static func days(_ days: [ScheduleWeekday]) -> String {
        let set = Set(days)
        if set.count == ScheduleWeekday.allCases.count { return "Every day" }
        let names: [ScheduleWeekday: String] = [.mo: "Mon", .tu: "Tue", .we: "Wed", .th: "Thu",
                                                .fr: "Fri", .sa: "Sat", .su: "Sun"]
        return set.sorted().compactMap { names[$0] }.joined(separator: ", ")
    }

    /// "08:00" → "8:00 AM". The time is already the receiver's wall clock.
    static func clock(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return hhmm }
        let hour12 = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d %@", hour12, parts[1], parts[0] < 12 ? "AM" : "PM")
    }

    /// "Mon, Wed, Fri · every week · 8:00 AM"; "Every day · 8:00 AM" on all seven days
    /// every week; "All week · every 2 weeks · 8:00 AM" on all seven days of every
    /// other week (Figma 428:4179).
    static func scheduleLine(_ s: TrackerScheduleItem) -> String {
        let allWeek = Set(s.days).count == ScheduleWeekday.allCases.count
        let parts: [String]
        switch (allWeek, s.interval == 1) {
        case (true, true): parts = ["Every day", clock(s.time)]
        case (true, false): parts = ["All week", frequency(intervalWeeks: s.interval), clock(s.time)]
        case (false, _): parts = [days(s.days), frequency(intervalWeeks: s.interval), clock(s.time)]
        }
        return parts.joined(separator: " · ")
    }

    static let alertsIfUnrecorded = "Alerts the team if it goes unrecorded"

    // MARK: Helpers

    /// "3 days", "1 day", "12 hours".
    static func duration(hours: Int) -> String {
        hours >= 24 && hours % 24 == 0 ? plural(hours / 24, "day") : plural(hours, "hour")
    }

    /// 154.2 → "154.2", 128 → "128", 1.234 → "1.23".
    static func number(_ n: Double) -> String {
        if n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
        var s = String(format: "%.2f", n)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func withUnit(_ value: String, _ unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }

    private static func plural(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }

    /// "Nov 3", or "Nov 3, 2025" outside the current year.
    private static func shortDate(_ date: Date, now: Date, zone: TimeZone) -> String {
        let calendar = calendar(zone)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(date, sameYear ? "MMM d" : "MMM d, yyyy", zone)
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        Formatters.shared.format(date, pattern, zone)
    }

    private static func parseISO(_ s: String) -> Date? {
        Formatters.shared.parseISO(s)
    }

    /// `yyyy-MM-dd` for `date` in `zone` — the shape `from`/`to` take.
    static func dayString(_ date: Date, zone: TimeZone) -> String {
        format(date, "yyyy-MM-dd", zone)
    }
}

/// TrackerText's formatters, built once per (pattern, zone) and reused: a list of
/// entries formats several dates a row, and a DateFormatter is costly to make.
/// Every use is under `lock`, so any thread may call it.
private final class Formatters: @unchecked Sendable {
    static let shared = Formatters()

    private struct Key: Hashable {
        let pattern: String
        let zone: String
    }

    private let lock = NSLock()
    private var dateFormatters: [Key: DateFormatter] = [:]
    private let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let iso = ISO8601DateFormatter()

    func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        lock.withLock {
            let key = Key(pattern: pattern, zone: zone.identifier)
            let formatter: DateFormatter
            if let cached = dateFormatters[key] {
                formatter = cached
            } else {
                formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = zone
                formatter.dateFormat = pattern
                dateFormatters[key] = formatter
            }
            return formatter.string(from: date)
        }
    }

    func parseISO(_ s: String) -> Date? {
        lock.withLock { isoWithFraction.date(from: s) ?? iso.date(from: s) }
    }
}
