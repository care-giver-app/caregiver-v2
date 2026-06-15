import Foundation
import CaregiverAPI

@MainActor
@Observable
final class TrackerDetailModel {
    enum State: Equatable {
        case loading
        case loaded([Components.Schemas.Event])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private var cursor: String?
    private(set) var isLoadingMore = false
    private(set) var hasMore = false

    private let pageSize = 25

    func load(trackerId: String, using session: Session) async {
        state = .loading; cursor = nil
        do {
            let page = try await fetch(trackerId: trackerId, cursor: nil, using: session)
            cursor = page.nextCursor; hasMore = page.nextCursor != nil
            state = page.items.isEmpty ? .empty : .loaded(page.items)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }

    func loadMoreIfNeeded(current event: Components.Schemas.Event, trackerId: String, using session: Session) async {
        guard case .loaded(let items) = state, hasMore, !isLoadingMore,
              event.eventId == items.last?.eventId else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        do {
            let page = try await fetch(trackerId: trackerId, cursor: cursor, using: session)
            cursor = page.nextCursor; hasMore = page.nextCursor != nil
            state = .loaded(items + page.items)
        } catch { /* keep what we have; transient */ }
    }

    private func fetch(trackerId: String, cursor: String?, using session: Session) async throws -> Components.Schemas.EventList {
        let response = try await session.api.listEvents(
            path: .init(trackerId: trackerId),
            query: .init(limit: pageSize, cursor: cursor)
        )
        return try response.ok.body.json
    }

    func rename(tracker: Components.Schemas.Tracker, to name: String, using session: Session) async -> String? {
        do {
            let body = Components.Schemas.TrackerWrite(
                name: name, kind: tracker.kind, icon: tracker.icon, color: tracker.color, fields: tracker.fields
            )
            _ = try await session.api.updateTracker(path: .init(trackerId: tracker.trackerId), body: .json(body))
            return nil
        } catch { return AppError.from(error).message }
    }

    func archive(trackerId: String, using session: Session) async -> String? {
        do {
            _ = try await session.api.archiveTracker(path: .init(trackerId: trackerId))
            return nil
        } catch { return AppError.from(error).message }
    }
}
