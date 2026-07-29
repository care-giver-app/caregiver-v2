import Foundation
import CaregiverAPI

/// One tracker + its most recent event, with the derived presentation facts
/// shared by Home's snapshot tiles and the Trackers rows (home.md decision 6).
struct TrackerSummary: Identifiable, Equatable {
    let tracker: Components.Schemas.Tracker
    let lastEvent: Components.Schemas.Event?

    var id: String { tracker.trackerId }
    var lastOccurredAt: Date? { lastEvent?.occurredAt }

    /// Friendly kind label per the mapping table in ios/specs/sample-data.md.
    var kindLabel: String {
        TrackerSummariesModel.kindLabel(kind: tracker.kind, fields: tracker.fields)
    }

    /// Human summary of the last event's values ("128/82 mmHg"), nil when never logged.
    var lastValueText: String? {
        guard let lastEvent else { return nil }
        let text = DynamicFormBuilder.display(values: lastEvent.values, fields: tracker.fields)
        return text.isEmpty ? nil : text
    }

    /// Recency-as-luminance state. `.overdue` is NEVER produced — the contract has
    /// no schedule/cadence until B3b (home.md decision 8).
    func recency(now: Date = Date()) -> StrideTrackerRecency {
        guard let lastOccurredAt else { return .normal }
        return now.timeIntervalSince(lastOccurredAt) < 24 * 3600 ? .fresh : .normal
    }

    /// Never-logged or 7+ days silent — the "Needs attention" filter
    /// (trackers.md decision 6). A soft "quiet lately" signal, not a "Due" claim.
    func needsAttention(now: Date = Date()) -> Bool {
        guard let lastOccurredAt else { return true }
        return now.timeIntervalSince(lastOccurredAt) >= 7 * 24 * 3600
    }

    /// "30m ago" / "2h ago" / "Yesterday" / "3d ago" / "Jun 12"; "in 30m" / "in 2h" /
    /// "Tomorrow" / "in 3d" for a future `occurred_at` (e.g. a Doctor Appointment
    /// logged ahead of the visit); nil when never logged.
    func recencyText(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let lastOccurredAt else { return nil }
        let seconds = now.timeIntervalSince(lastOccurredAt)
        if seconds < 0 {
            return Self.futureRecencyText(secondsUntil: -seconds, from: lastOccurredAt, now: now, calendar: calendar)
        }
        if seconds < 3600 {
            return "\(max(1, Int(seconds / 60)))m ago"
        }
        let startToday = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday),
           calendar.isDate(lastOccurredAt, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if seconds < 24 * 3600 {
            return "\(Int(seconds / 3600))h ago"
        }
        let days = Int(seconds / 86400)
        if days < 7 {
            return "\(max(1, days))d ago"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: lastOccurredAt)
    }

    /// Mirror of the past-date buckets in `recencyText`, for a future `occurred_at`.
    private static func futureRecencyText(secondsUntil: TimeInterval, from date: Date, now: Date, calendar: Calendar) -> String {
        if secondsUntil < 3600 {
            return "in \(max(1, Int(secondsUntil / 60)))m"
        }
        let startToday = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startToday),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if secondsUntil < 24 * 3600 {
            return "in \(Int(secondsUntil / 3600))h"
        }
        let days = Int(secondsUntil / 86400)
        if days < 7 {
            return "in \(max(1, days))d"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

/// Loads all of a receiver's trackers (including archived) plus each tracker's
/// most recent event (`listEvents(limit: 1)` — the server returns newest first).
@MainActor
@Observable
final class TrackerSummariesModel {
    enum State: Equatable {
        case loading
        case loaded([TrackerSummary])
        case error(String)
    }

    private(set) var state: State = .loading

    /// Non-archived summaries, attention-first (never-logged → stalest → freshest).
    var active: [TrackerSummary] {
        guard case .loaded(let all) = state else { return [] }
        return Self.attentionFirst(all.filter { !$0.tracker.archived }, now: Date())
    }

    var archived: [TrackerSummary] {
        guard case .loaded(let all) = state else { return [] }
        return all.filter { $0.tracker.archived }
    }

    func load(receiverID: String, using session: Session) async {
        state = .loading
        let api = session.api  // capture the Sendable client for child tasks
        do {
            let trackers = try await api.listTrackers(path: .init(receiverId: receiverID))
                .ok.body.json
            let summaries = try await withThrowingTaskGroup(of: TrackerSummary.self) { group in
                for tracker in trackers {
                    group.addTask {
                        let last = try await api.listEvents(
                            path: .init(trackerId: tracker.trackerId),
                            query: .init(limit: 1)
                        ).ok.body.json.items.first
                        return TrackerSummary(tracker: tracker, lastEvent: last)
                    }
                }
                var results: [TrackerSummary] = []
                for try await summary in group { results.append(summary) }
                return results
            }
            state = .loaded(summaries)
        } catch {
            if error is CancellationError { return }
            state = .error(AppError.from(error).message)
        }
    }

    /// Clears any prior receiver's data — used when no receiver is active
    /// (fresh group, or sign-out) so stale tiles never render.
    func reset() {
        state = .loaded([])
    }

    /// Kind → friendly label, per the sample-data.md mapping table.
    nonisolated static func kindLabel(
        kind: Components.Schemas.TrackerKind,
        fields: [Components.Schemas.Field]
    ) -> String {
        if kind == .scheduled { return "Checklist" }
        if fields.isEmpty { return "Quick log" }
        if fields.contains(where: { $0._type == ._enum }) { return "Scale" }
        if let number = fields.first(where: { $0._type == .number }) {
            if isTimeUnit(number.unit) { return "Duration" }
            return kind == .measurement ? "Numeric" : "Count"
        }
        return kind == .measurement ? "Numeric" : "Count"
    }

    private nonisolated static func isTimeUnit(_ unit: String?) -> Bool {
        guard let unit = unit?.lowercased() else { return false }
        return ["h", "hr", "hrs", "hour", "hours", "m", "min", "mins", "minute", "minutes", "s", "sec", "secs", "second", "seconds"]
            .contains(unit)
    }

    /// Attention group first (never-logged, then oldest-logged), then the rest
    /// stalest-first; ties broken by name for determinism.
    nonisolated static func attentionFirst(_ summaries: [TrackerSummary], now: Date) -> [TrackerSummary] {
        summaries.sorted { lhs, rhs in
            let lhsAttention = lhs.needsAttention(now: now)
            let rhsAttention = rhs.needsAttention(now: now)
            if lhsAttention != rhsAttention { return lhsAttention }
            switch (lhs.lastOccurredAt, rhs.lastOccurredAt) {
            case (nil, nil): return lhs.tracker.name < rhs.tracker.name
            case (nil, _): return true
            case (_, nil): return false
            case (let l?, let r?):
                if l != r { return l < r }
                return lhs.tracker.name < rhs.tracker.name
            }
        }
    }
}
