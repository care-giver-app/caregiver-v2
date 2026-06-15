import Foundation
import CaregiverAPI

@MainActor
@Observable
final class ReceiversListModel {
    enum State: Equatable {
        case loading
        case loaded([Components.Schemas.Receiver])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading

    func load(using session: Session) async {
        state = .loading
        do {
            let response = try await session.api.listReceivers(query: .init(careGroupId: nil))
            let receivers = try response.ok.body.json.filter { !$0.archived }
            state = receivers.isEmpty ? .empty : .loaded(receivers)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }
}
