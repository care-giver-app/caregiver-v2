import SwiftUI

/// Every screen pushed on the signed-in `/v1` stack. The stack is driven by one
/// path of these and one `navigationDestination(for:)` at its root, because
/// SwiftUI mis-orders a stack that mixes value pushes with `isPresented` or
/// `item` destinations: the value-pushed screen lands beneath the other one, so
/// a tap only flashes and Back reveals the screen it should have shown.
///
/// Whether the caller may manage trackers rides on each route's `TeamReceiver`
/// (`canManage`), so every pushed screen knows without reaching for the account.
enum V1Route: Hashable {
    case trackers(TeamReceiver)
    case tracker(id: String, receiver: TeamReceiver)
    case schedules(trackerID: String, trackerName: String, receiver: TeamReceiver)
}

extension View {
    /// Registers every `V1Route` destination. Apply once, at the stack's root.
    func v1Destinations(service: TrackersService) -> some View {
        navigationDestination(for: V1Route.self) { route in
            switch route {
            case .trackers(let receiver):
                TrackersV1View(receiver: receiver, service: service)
            case .tracker(let id, let receiver):
                TrackerDetailV1View(trackerID: id, receiver: receiver, service: service)
            case .schedules(let trackerID, let trackerName, let receiver):
                SchedulesV1View(trackerID: trackerID, trackerName: trackerName, receiver: receiver,
                                service: service)
            }
        }
    }
}

/// Appends a route to the one `/v1` stack, for a screen that must push without a
/// `NavigationLink` — Trackers, landing on a tracker Add tracker just made. RootView,
/// which owns the stack's path, supplies it; elsewhere it does nothing.
struct V1Push: Sendable {
    let push: @MainActor @Sendable (V1Route) -> Void

    @MainActor func callAsFunction(_ route: V1Route) { push(route) }
}

private struct V1PushKey: EnvironmentKey {
    static let defaultValue = V1Push { _ in }
}

extension EnvironmentValues {
    var v1Push: V1Push {
        get { self[V1PushKey.self] }
        set { self[V1PushKey.self] = newValue }
    }
}
