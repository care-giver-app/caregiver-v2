import Foundation

/// The two look-ahead sections on the "Coming up" screen
/// (ios/specs/views/schedule.md). Only non-empty buckets render.
enum ScheduleBucket: CaseIterable, Equatable {
    case thisWeek, later

    var title: String {
        switch self {
        case .thisWeek: return "This week"
        case .later: return "Later"
        }
    }
}

/// Pure relative-time helpers for the schedule look-ahead. Kept free of any
/// SwiftUI/network dependency so the labelling and bucketing are unit-testable.
enum ScheduleTime {
    /// Whole-calendar-day difference from `now` to `date` (negative = in the past).
    static func dayOffset(to date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// The meta label shown per row and in the Home banner: "Overdue" / "Today" /
    /// "Tomorrow" / "in N days". Always relative (never an absolute date) within the
    /// look-ahead window — mirrors the approved Figma "Coming up" frame.
    static func relativeLabel(to date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch dayOffset(to: date, now: now, calendar: calendar) {
        case ..<0: return "Overdue"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case let days: return "in \(days) days"
        }
    }

    /// Groups an item: within the coming week (`< 7` calendar days) is "This week",
    /// everything further out is "Later".
    static func bucket(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> ScheduleBucket {
        dayOffset(to: date, now: now, calendar: calendar) < 7 ? .thisWeek : .later
    }
}
