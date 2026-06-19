import XCTest
@testable import Caregiver

final class MeTeamNameTests: XCTestCase {
    private func me(_ memberships: [Me.Membership]) -> Me {
        Me(userName: "Ann", memberships: memberships)
    }

    func testReturnsTeamNameForKnownGroup() {
        let m = me([.init(careGroupID: "g1", name: "The Williams Family", role: "admin")])
        XCTAssertEqual(m.teamName(forCareGroup: "g1"), "The Williams Family")
    }

    func testReturnsNilForUnknownGroup() {
        let m = me([.init(careGroupID: "g1", name: "The Williams Family", role: "admin")])
        XCTAssertNil(m.teamName(forCareGroup: "other"))
    }

    func testPicksCorrectTeamAmongMany() {
        let m = me([
            .init(careGroupID: "g1", name: "Home", role: "admin"),
            .init(careGroupID: "g2", name: "Mom's Team", role: "caregiver"),
        ])
        XCTAssertEqual(m.teamName(forCareGroup: "g2"), "Mom's Team")
    }
}
