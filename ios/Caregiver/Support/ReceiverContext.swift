import Foundation
import CaregiverAPI

@MainActor
@Observable
final class ReceiverContext {
    var receivers: [Components.Schemas.Receiver] = []
    private(set) var isLoaded = false

    var activeReceiverID: String? {
        didSet { UserDefaults.standard.set(activeReceiverID, forKey: "activeReceiverID") }
    }

    var activeReceiver: Components.Schemas.Receiver? {
        receivers.first { $0.receiverId == activeReceiverID } ?? receivers.first
    }

    init() {
        activeReceiverID = UserDefaults.standard.string(forKey: "activeReceiverID")
    }

    func load(using session: Session) async {
        do {
            let response = try await session.api.listReceivers(query: .init(careGroupId: nil))
            receivers = try response.ok.body.json.filter { !$0.archived }
            if activeReceiverID != nil && activeReceiver == nil {
                activeReceiverID = nil
            }
        } catch {}
        isLoaded = true
    }

    func setActive(_ receiver: Components.Schemas.Receiver) {
        activeReceiverID = receiver.receiverId
    }
}
