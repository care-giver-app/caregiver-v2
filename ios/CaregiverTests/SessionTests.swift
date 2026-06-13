import XCTest
@testable import Caregiver

@MainActor
final class SessionTests: XCTestCase {
    func testNoMembershipsGoesToOnboarding() async {
        let session = Session(bootstrap: { .init(userName: "Ann", memberships: []) },
                              signOutHandler: {})
        await session.refresh()
        guard case .onboarding = session.state else {
            return XCTFail("expected onboarding, got \(session.state)")
        }
    }

    func testWithMembershipsGoesToReady() async {
        let session = Session(
            bootstrap: { .init(userName: "Ann", memberships: [.init(careGroupID: "g1", name: "Home", role: "admin")]) },
            signOutHandler: {}
        )
        await session.refresh()
        guard case .ready = session.state else {
            return XCTFail("expected ready, got \(session.state)")
        }
    }

    func testBootstrapFailureGoesToSignedOut() async {
        struct Boom: Error {}
        let session = Session(bootstrap: { throw Boom() }, signOutHandler: {})
        await session.refresh()
        guard case .signedOut = session.state else {
            return XCTFail("expected signedOut, got \(session.state)")
        }
    }
}
