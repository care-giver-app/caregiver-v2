import Foundation
import CaregiverAPI

/// Pure grouping logic for the receiver switch sheet (receivers.md decision 1):
/// receivers grouped under their care-group membership, the active group first,
/// memberships with no receivers dropped. Kept free of view/state so it is
/// unit-testable in isolation (mirrors `QuickLogWizardModel`'s pure-statics style).
enum ReceiverSwitcher {
    struct Group {
        let membership: Me.Membership
        let receivers: [Components.Schemas.Receiver]
    }

    static func groups(
        memberships: [Me.Membership],
        receivers: [Components.Schemas.Receiver],
        activeGroupID: String?
    ) -> [Group] {
        memberships
            .sorted { lhs, rhs in
                let lhsActive = lhs.careGroupID == activeGroupID
                let rhsActive = rhs.careGroupID == activeGroupID
                if lhsActive != rhsActive { return lhsActive }
                return false
            }
            .compactMap { membership in
                let owned = receivers.filter { $0.careGroupId == membership.careGroupID }
                return owned.isEmpty ? nil : Group(membership: membership, receivers: owned)
            }
    }
}
