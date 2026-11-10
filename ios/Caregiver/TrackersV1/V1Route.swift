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

extension V1Route {
    /// `path` taken back to its last Trackers list — where Pause lands (PRD "Pause this
    /// tracker?"). With no Trackers list on it, back to the stack's root.
    static func poppedToTrackers(_ path: [V1Route]) -> [V1Route] {
        guard let i = path.lastIndex(where: { if case .trackers = $0 { true } else { false } }) else { return [] }
        return Array(path[...i])
    }
}

/// Takes the one `/v1` stack back to its Trackers list, for a pushed screen that must go
/// back further than its own Back — Tracker detail or Schedules once their tracker is
/// paused. RootView, which owns the stack's path, supplies it; elsewhere it does nothing.
struct V1PopToTrackers: Sendable {
    let pop: @MainActor @Sendable () -> Void

    @MainActor func callAsFunction() { pop() }
}

private struct V1PopToTrackersKey: EnvironmentKey {
    static let defaultValue = V1PopToTrackers {}
}

extension EnvironmentValues {
    var v1PopToTrackers: V1PopToTrackers {
        get { self[V1PopToTrackersKey.self] }
        set { self[V1PopToTrackersKey.self] = newValue }
    }
}
