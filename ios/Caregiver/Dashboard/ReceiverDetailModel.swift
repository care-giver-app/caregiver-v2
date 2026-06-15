import Foundation
import CaregiverAPI

@MainActor
@Observable
final class ReceiverDetailModel {
    enum State: Equatable {
        case loading
        case loaded([Components.Schemas.Tracker])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading

    func load(receiverId: String, using session: Session) async {
        state = .loading
        do {
            let response = try await session.api.listTrackers(path: .init(receiverId: receiverId))
            let trackers = try response.ok.body.json.filter { !$0.archived }
            state = trackers.isEmpty ? .empty : .loaded(trackers)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }

    /// Returns an error message on failure, nil on success.
    func rename(receiverId: String, to name: String, using session: Session) async -> String? {
        do {
            _ = try await session.api.updateReceiver(path: .init(receiverId: receiverId), body: .json(.init(name: name)))
            return nil
        } catch { return AppError.from(error).message }
    }

    func archive(receiverId: String, using session: Session) async -> String? {
        do {
            _ = try await session.api.archiveReceiver(path: .init(receiverId: receiverId))
            return nil
        } catch { return AppError.from(error).message }
    }
}
