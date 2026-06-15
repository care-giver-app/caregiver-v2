import XCTest
@testable import Caregiver

final class RoleGatingTests: XCTestCase {
    private func me(_ memberships: [Me.Membership]) -> Me {
        Me(userName: "Ann", memberships: memberships)
    }

    func testIsAdminWhenRoleIsAdmin() {
        let m = me([.init(careGroupID: "g1", name: "Home", role: "admin")])
        XCTAssertTrue(m.isAdmin(inCareGroup: "g1"))
    }

    func testIsNotAdminWhenRoleIsCaregiver() {
        let m = me([.init(careGroupID: "g1", name: "Home", role: "caregiver")])
        XCTAssertFalse(m.isAdmin(inCareGroup: "g1"))
    }

    func testIsNotAdminForUnknownGroup() {
        let m = me([.init(careGroupID: "g1", name: "Home", role: "admin")])
        XCTAssertFalse(m.isAdmin(inCareGroup: "other"))
    }

    func testAdminGroupsReturnsOnlyAdminMemberships() {
        let m = me([
            .init(careGroupID: "g1", name: "Home", role: "admin"),
            .init(careGroupID: "g2", name: "Mom", role: "caregiver"),
        ])
        XCTAssertEqual(m.adminGroups.map(\.careGroupID), ["g1"])
    }
}
