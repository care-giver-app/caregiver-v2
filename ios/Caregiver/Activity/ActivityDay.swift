import Foundation

/// Pure date helpers for the Activity daily timeline.
enum ActivityDay {
    /// The half-open day window `[startOfDay, nextMidnight)` for `date` in `calendar`.
    static func bounds(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    /// "Today" / "Yesterday" / weekday + medium date (e.g. "Sun, Jun 14").
    static func label(for date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let startToday = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}
