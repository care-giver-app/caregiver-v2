import Foundation
import CaregiverAPI

/// Couples a tracker with one of its events for the event-detail route.
struct EventRef: Hashable {
    let tracker: Components.Schemas.Tracker
    let event: Components.Schemas.Event
}

/// Navigation destinations for the main NavigationStack. Generated schema types
/// are Hashable, so they nest in a Hashable enum.
enum Route: Hashable {
    case receiver(Components.Schemas.Receiver)
    case tracker(Components.Schemas.Tracker)
    case event(EventRef)
}
