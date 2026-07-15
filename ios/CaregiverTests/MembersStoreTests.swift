import XCTest
import CaregiverAPI
@testable import Caregiver

final class MembersStoreTests: XCTestCase {
    private func member(_ id: String, _ name: String) -> Components.Schemas.Member {
        .init(userId: id, name: name, role: .caregiver)
    }

    func testReturnsNameWhenPresent() {
        let members = [member("u1", "Una"), member("u2", "Dos")]
        XCTAssertEqual(MemberDirectory.displayName(forUser: "u2", in: members), "Dos")
    }

    func testFallsBackWhenAbsent() {
        let members = [member("u1", "Una")]
        XCTAssertEqual(MemberDirectory.displayName(forUser: "ghost", in: members), "A care-team member")
    }

    func testFallsBackWhenEmpty() {
        XCTAssertEqual(MemberDirectory.displayName(forUser: "u1", in: []), "A care-team member")
    }
}
