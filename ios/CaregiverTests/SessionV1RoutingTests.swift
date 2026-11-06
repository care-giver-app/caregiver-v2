import XCTest
import CaregiverAPI
@testable import Caregiver

/// Flag `v1_api` decides which sign-in resolution runs. Off — or unknown — keeps
/// today's `GET /me` path exactly.
@MainActor
final class SessionV1RoutingTests: XCTestCase {
    private let oldMe = Me(userName: "Trevor", memberships: [
        .init(careGroupID: "g1", name: "The Riverside Group", role: "admin"),
    ])
    private let noTeam = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [])
    private let onTeam = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [
        .init(teamID: "t1", name: "The Riverside Group", role: "admin"),
    ])

    private func session(flags: @escaping @Sendable () async throws -> FeatureFlags,
                         account: Account? = nil,
                         flagsTimeout: Duration = .seconds(5)) -> Session {
        let v1 = account
        return Session(
            bootstrap: { [oldMe] in oldMe },
            bootstrapV1: {
                guard let v1 else { throw Session.NotSignedIn() }
                return v1
            },
            fetchFlags: flags,
            flagsTimeout: flagsTimeout,
            signOutHandler: {}
        )
    }

    func testFlagOffKeepsTheOldPath() async {
        let s = session(flags: { FeatureFlags(enabled: ["flags_demo"]) }, account: onTeam)
        await s.refresh()
        XCTAssertEqual(s.state, .ready(oldMe))
    }

    func testFlagOnWithNoTeamGoesToJoinACareTeam() async {
        let s = session(flags: { FeatureFlags(enabled: [FeatureFlags.v1API]) }, account: noTeam)
        await s.refresh()
        XCTAssertEqual(s.state, .v1NoTeam(noTeam))
    }

    func testFlagOnWithATeamGoesToV1Ready() async {
        let s = session(flags: { FeatureFlags(enabled: [FeatureFlags.v1API]) }, account: onTeam)
        await s.refresh()
        XCTAssertEqual(s.state, .v1Ready(onTeam))
    }

    func testFlagFetchFailureReadsAsOff() async {
        struct Boom: Error {}
        let s = session(flags: { throw Boom() }, account: onTeam)
        await s.refresh()
        XCTAssertEqual(s.state, .ready(oldMe))
    }

    func testSlowFlagFetchTimesOutAsOff() async {
        let s = session(flags: {
            try await Task.sleep(for: .seconds(30))
            return FeatureFlags(enabled: [FeatureFlags.v1API])
        }, account: onTeam, flagsTimeout: .milliseconds(50))
        await s.refresh()
        XCTAssertEqual(s.state, .ready(oldMe))
    }

    func testFlagOnButV1BootstrapFailsGoesToSignedOut() async {
        let s = session(flags: { FeatureFlags(enabled: [FeatureFlags.v1API]) }, account: nil)
        await s.refresh()
        XCTAssertEqual(s.state, .signedOut)
    }

    func testSignOutFromV1Ready() async {
        let s = session(flags: { FeatureFlags(enabled: [FeatureFlags.v1API]) }, account: onTeam)
        await s.refresh()
        await s.signOut()
        XCTAssertEqual(s.state, .signedOut)
        XCTAssertTrue(s.signedOutExplicitly)
    }

    // MARK: - Reading GET /flags

    private func flags(_ json: String) throws -> FeatureFlags {
        FeatureFlags(try JSONDecoder().decode(Components.Schemas.Flags.self, from: Data(json.utf8)))
    }

    func testV1APIEnabledIsOn() throws {
        let f = try flags(#"{"flags_demo":{"enabled":false},"v1_api":{"enabled":true}}"#)
        XCTAssertTrue(f.isEnabled(FeatureFlags.v1API))
        XCTAssertFalse(f.isEnabled("flags_demo"))
    }

    func testMissingFlagIsOff() throws {
        XCTAssertFalse(try flags(#"{"flags_demo":{"enabled":true}}"#).isEnabled(FeatureFlags.v1API))
        XCTAssertFalse(try flags(#"{}"#).isEnabled(FeatureFlags.v1API))
    }

    func testNonBoolFlagIsOff() throws {
        XCTAssertFalse(try flags(#"{"v1_api":{"enabled":"true"}}"#).isEnabled(FeatureFlags.v1API))
        XCTAssertFalse(try flags(#"{"v1_api":{"enabled":1}}"#).isEnabled(FeatureFlags.v1API))
        XCTAssertFalse(try flags(#"{"v1_api":true}"#).isEnabled(FeatureFlags.v1API))
        XCTAssertFalse(try flags(#"{"v1_api":{}}"#).isEnabled(FeatureFlags.v1API))
        XCTAssertFalse(try flags(#"{"v1_api":{"enabled":null}}"#).isEnabled(FeatureFlags.v1API))
    }

    func testMissingFlagThroughSessionIsOff() async throws {
        let parsed = try flags(#"{"flags_demo":{"enabled":true}}"#)
        let s = session(flags: { parsed }, account: onTeam)
        await s.refresh()
        XCTAssertEqual(s.state, .ready(oldMe))
    }
}
