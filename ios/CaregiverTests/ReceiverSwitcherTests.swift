import XCTest
import CaregiverAPI
@testable import Caregiver

final class ReceiverSwitcherTests: XCTestCase {
    private func membership(_ id: String, _ name: String, role: String = "admin") -> Me.Membership {
        .init(careGroupID: id, name: name, role: role)
    }

    private func receiver(_ id: String, group: String) -> Components.Schemas.Receiver {
        .init(receiverId: id, careGroupId: group, name: id.capitalized,
              createdBy: "me", createdAt: Date(), archived: false)
    }

    private func groupIDs(_ groups: [ReceiverSwitcher.Group]) -> [String] {
        groups.map { $0.membership.careGroupID }
    }

    private func receiverIDs(_ groups: [ReceiverSwitcher.Group]) -> [[String]] {
        groups.map { $0.receivers.map(\.receiverId) }
    }

    func testGroupsReceiversUnderTheirMembership() {
        let groups = ReceiverSwitcher.groups(
            memberships: [membership("g1", "Riverside"), membership("g2", "Elm")],
            receivers: [receiver("eleanor", group: "g1"), receiver("harold", group: "g2")],
            activeGroupID: "g1"
        )
        XCTAssertEqual(groupIDs(groups), ["g1", "g2"])
        XCTAssertEqual(receiverIDs(groups), [["eleanor"], ["harold"]])
    }

    func testDropsMembershipsWithNoReceivers() {
        let groups = ReceiverSwitcher.groups(
            memberships: [membership("g1", "Riverside"), membership("empty", "Empty")],
            receivers: [receiver("eleanor", group: "g1")],
            activeGroupID: "g1"
        )
        XCTAssertEqual(groupIDs(groups), ["g1"])
    }

    func testActiveGroupSortsFirst() {
        let groups = ReceiverSwitcher.groups(
            memberships: [membership("g1", "Riverside"), membership("g2", "Elm")],
            receivers: [receiver("eleanor", group: "g1"), receiver("harold", group: "g2")],
            activeGroupID: "g2"
        )
        XCTAssertEqual(groupIDs(groups), ["g2", "g1"])
    }

    func testNilActiveGroupPreservesMembershipOrder() {
        let groups = ReceiverSwitcher.groups(
            memberships: [membership("g1", "Riverside"), membership("g2", "Elm")],
            receivers: [receiver("eleanor", group: "g1"), receiver("harold", group: "g2")],
            activeGroupID: nil
        )
        XCTAssertEqual(groupIDs(groups), ["g1", "g2"])
    }

    func testMultipleReceiversKeptInInputOrder() {
        let groups = ReceiverSwitcher.groups(
            memberships: [membership("g1", "Riverside")],
            receivers: [receiver("eleanor", group: "g1"),
                        receiver("harold", group: "g1"),
                        receiver("rosa", group: "g1")],
            activeGroupID: "g1"
        )
        XCTAssertEqual(receiverIDs(groups), [["eleanor", "harold", "rosa"]])
    }
}
