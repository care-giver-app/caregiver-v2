import Foundation
import CaregiverAPI

@MainActor
@Observable
final class ActivityModel {
    enum State: Equatable {
        case loading
        case loaded([EventRef])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading

    /// Flattens per-tracker events into `EventRef`s, oldest-first (earliest event first); ties
    /// broken by `eventId` ascending so the order is deterministic.
    nonisolated static func merge(_ perTracker: [(Components.Schemas.Tracker, [Components.Schemas.Event])]) -> [EventRef] {
        perTracker
            .flatMap { tracker, events in events.map { EventRef(tracker: tracker, event: $0) } }
            .sorted { lhs, rhs in
                if lhs.event.occurredAt != rhs.event.occurredAt {
                    return lhs.event.occurredAt < rhs.event.occurredAt
                }
                return lhs.event.eventId < rhs.event.eventId
            }
    }

    /// Loads the active receiver's events for `date` across all its (non-archived) trackers.
    func load(receiverID: String, date: Date, using session: Session) async {
        state = .loading
        let bounds = ActivityDay.bounds(for: date)
        let api = session.api  // capture the Sendable client for use in child tasks
        do {
            let trackers = try await api.listTrackers(path: .init(receiverId: receiverID))
                .ok.body.json.filter { !$0.archived }
            let perTracker = try await withThrowingTaskGroup(
                of: (Components.Schemas.Tracker, [Components.Schemas.Event]).self
            ) { group in
                for tracker in trackers {
                    group.addTask {
                        // One day per tracker fits within the server page cap, so we take the
                        // first page and ignore next_cursor (merged-stream pagination is a
                        // deliberate non-goal — see the activity-timeline design spec).
                        let items = try await api.listEvents(
                            path: .init(trackerId: tracker.trackerId),
                            query: .init(from: bounds.start, to: bounds.end)
                        ).ok.body.json.items
                        return (tracker, items)
                    }
                }
                var results: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = []
                for try await pair in group { results.append(pair) }
                return results
            }
            let refs = Self.merge(perTracker)
            state = refs.isEmpty ? .empty : .loaded(refs)
        } catch {
            if error is CancellationError { return }
            state = .error(AppError.from(error).message)
        }
    }
}
