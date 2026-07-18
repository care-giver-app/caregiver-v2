import Foundation
import SwiftUI
import CaregiverAPI

/// One upcoming scheduled item joined to its tracker, ready for the row UI.
/// The scheduled-items contract carries only `tracker_id`, so name + hue are
/// resolved from the tracker (ios/specs/views/schedule.md).
struct UpcomingItem: Identifiable, Equatable {
    let id: String
    let tracker: Components.Schemas.Tracker
    let scheduledFor: Date
    let note: String?

    var name: String { tracker.name }

    /// Detail line — the item's note, or nil when blank (the section header and
    /// meta label already convey the timing).
    var subtitle: String? {
        guard let note, !note.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return note
    }

    var hue: Color { tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent }

    func relativeLabel(now: Date = Date()) -> String {
        ScheduleTime.relativeLabel(to: scheduledFor, now: now)
    }

    func bucket(now: Date = Date()) -> ScheduleBucket {
        ScheduleTime.bucket(for: scheduledFor, now: now)
    }
}

/// Loads the active receiver's upcoming scheduled items across all its trackers
/// and joins them to tracker name/hue. Feeds both the Home "Coming up" banner
/// (`next`) and the pushed schedule list (`items`). Mirrors `ActivityModel`.
@MainActor
@Observable
final class ScheduleModel {
    enum State: Equatable {
        case loading
        case loaded([UpcomingItem])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading

    /// How far ahead the look-ahead window reaches.
    static let windowDays = 60

    var items: [UpcomingItem] {
        if case .loaded(let items) = state { return items }
        return []
    }

    /// The single soonest upcoming item — drives the Home banner.
    var next: UpcomingItem? { items.first }

    /// Joins scheduled items (already soonest-first from the server) to their
    /// trackers; drops items whose tracker is missing or archived. Server order
    /// is preserved. `nonisolated` so it's testable without the network.
    nonisolated static func map(
        items: [Components.Schemas.ScheduledItem],
        trackers: [Components.Schemas.Tracker]
    ) -> [UpcomingItem] {
        let byID = Dictionary(trackers.map { ($0.trackerId, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item in
            guard let tracker = byID[item.trackerId], !tracker.archived else { return nil }
            return UpcomingItem(
                id: item.scheduledItemId, tracker: tracker,
                scheduledFor: item.scheduledFor, note: item.note
            )
        }
    }

    func load(receiverID: String, using session: Session, now: Date = Date()) async {
        state = .loading
        let api = session.api  // capture the Sendable client for child tasks
        do {
            let to = Calendar.current.date(byAdding: .day, value: Self.windowDays, to: now) ?? now
            let trackers = try await api.listTrackers(path: .init(receiverId: receiverID)).ok.body.json
            let scheduled = try await api.listReceiverScheduledItems(
                path: .init(receiverId: receiverID),
                query: .init(limit: 100, from: now, to: to)
            ).ok.body.json.items
            let upcoming = Self.map(items: scheduled, trackers: trackers)
            state = upcoming.isEmpty ? .empty : .loaded(upcoming)
        } catch {
            if error is CancellationError { return }
            state = .error(AppError.from(error).message)
        }
    }

    /// Clears any prior receiver's data — used when no receiver is active.
    func reset() { state = .empty }
}
