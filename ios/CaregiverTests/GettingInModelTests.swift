import XCTest
@testable import Caregiver

/// Records what a fake `GettingInService` was asked to do.
private actor Calls {
    var redeemed: [String] = []
    var created: [String] = []
    func redeem(_ code: String) { redeemed.append(code) }
    func create(_ name: String) { created.append(name) }
}

@MainActor
final class JoinCareTeamModelTests: XCTestCase {
    private let riverside = PendingInvitation(code: "abc123", teamName: "The Riverside Group", invitedByName: "Dana")

    private func make(redeem: @escaping @Sendable (String) async throws -> RedeemOutcome,
                      calls: Calls,
                      joined: @escaping () -> Void = {}) -> JoinCareTeamModel {
        let service = GettingInService(
            listInvitations: { [riverside] in [riverside] },
            redeem: { code in
                await calls.redeem(code)
                return try await redeem(code)
            },
            createTeam: { _ in .created }
        )
        return JoinCareTeamModel(service: service, onJoined: { joined() })
    }

    func testLoadListsInvitations() async {
        let model = make(redeem: { _ in .joined }, calls: Calls())
        await model.load()
        XCTAssertEqual(model.invitations, .loaded([riverside]))
    }

    func testLoadFailureIsShown() async {
        let model = JoinCareTeamModel(
            service: GettingInService(listInvitations: { throw URLError(.notConnectedToInternet) },
                                      redeem: { _ in .joined }, createTeam: { _ in .created }),
            onJoined: {}
        )
        await model.load()
        XCTAssertEqual(model.invitations, .failed(.transport))
    }

    func testAcceptRedeemsThatInvitationsCodeAndRefreshes() async {
        let calls = Calls()
        var joined = 0
        let model = make(redeem: { _ in .joined }, calls: calls, joined: { joined += 1 })
        await model.accept(riverside)
        let redeemed = await calls.redeemed
        XCTAssertEqual(redeemed, ["abc123"])
        XCTAssertEqual(joined, 1)
        XCTAssertNil(model.error)
        XCTAssertNil(model.acceptingCode)
    }

    func testPastedValidCodeIsTrimmedAndRefreshes() async {
        let calls = Calls()
        var joined = 0
        let model = make(redeem: { _ in .joined }, calls: calls, joined: { joined += 1 })
        model.code = "  xyz789\n"
        await model.joinWithCode()
        let redeemed = await calls.redeemed
        XCTAssertEqual(redeemed, ["xyz789"])
        XCTAssertEqual(joined, 1)
        XCTAssertFalse(model.isJoining)
    }

    func testBlankCodeMakesNoCall() async {
        let calls = Calls()
        let model = make(redeem: { _ in .joined }, calls: calls)
        model.code = "   "
        await model.joinWithCode()
        let redeemed = await calls.redeemed
        XCTAssertEqual(redeemed, [])
        XCTAssertNil(model.error)
    }

    func testCodeNoLongerValidStaysWithMessage() async {
        var joined = 0
        let model = make(redeem: { _ in .noLongerValid }, calls: Calls(), joined: { joined += 1 })
        model.code = "expired"
        await model.joinWithCode()
        XCTAssertEqual(model.error, JoinCareTeamModel.noLongerValid)
        XCTAssertEqual(model.error?.message, "This invite code is no longer valid")
        XCTAssertEqual(joined, 0)
    }

    func testAlreadyMemberShowsMessage() async {
        var joined = 0
        let model = make(redeem: { _ in .alreadyMember }, calls: Calls(), joined: { joined += 1 })
        await model.accept(riverside)
        XCTAssertEqual(model.error?.message, "You're already on this care team")
        XCTAssertEqual(joined, 0)
    }

    func testBadRequestShowsServerMessage() async {
        let model = make(redeem: { _ in .rejected("code is required") }, calls: Calls())
        model.code = "x"
        await model.joinWithCode()
        XCTAssertEqual(model.error?.message, "code is required")
    }

    func testNetworkErrorShowsTransportMessage() async {
        var joined = 0
        let model = make(redeem: { _ in throw URLError(.notConnectedToInternet) }, calls: Calls(),
                         joined: { joined += 1 })
        model.code = "abc"
        await model.joinWithCode()
        XCTAssertEqual(model.error, .transport)
        XCTAssertEqual(joined, 0)
        XCTAssertFalse(model.isJoining)
    }

    func testANewAttemptClearsTheLastMessage() async {
        var outcome = RedeemOutcome.noLongerValid
        let model = JoinCareTeamModel(
            service: GettingInService(listInvitations: { [] },
                                      redeem: { _ in await MainActor.run { outcome } },
                                      createTeam: { _ in .created }),
            onJoined: {}
        )
        model.code = "a"
        await model.joinWithCode()
        XCTAssertNotNil(model.error)
        outcome = .joined
        await model.joinWithCode()
        XCTAssertNil(model.error)
    }
}

@MainActor
final class CreateFirstCareTeamModelTests: XCTestCase {
    private func make(outcome: @escaping @Sendable () async throws -> CreateTeamOutcome,
                      calls: Calls,
                      created: @escaping () -> Void = {}) -> CreateFirstCareTeamModel {
        let service = GettingInService(
            listInvitations: { [] },
            redeem: { _ in .joined },
            createTeam: { name in
                await calls.create(name)
                return try await outcome()
            }
        )
        return CreateFirstCareTeamModel(service: service, onCreated: { created() })
    }

    func testBlankNameShowsMessageAndMakesNoCall() async {
        let calls = Calls()
        let model = make(outcome: { .created }, calls: calls)
        model.name = "  \n "
        await model.create()
        let created = await calls.created
        XCTAssertEqual(created, [])
        XCTAssertEqual(model.error, CreateFirstCareTeamModel.nameRequired)
    }

    func testSuccessTrimsTheNameAndRefreshes() async {
        let calls = Calls()
        var refreshed = 0
        let model = make(outcome: { .created }, calls: calls, created: { refreshed += 1 })
        model.name = "  The Riverside Group "
        await model.create()
        let created = await calls.created
        XCTAssertEqual(created, ["The Riverside Group"])
        XCTAssertEqual(refreshed, 1)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isBusy)
    }

    func testBadRequestShowsServerMessage() async {
        var refreshed = 0
        let model = make(outcome: { .rejected("name must be at most 100 characters") }, calls: Calls(),
                         created: { refreshed += 1 })
        model.name = "x"
        await model.create()
        XCTAssertEqual(model.error?.message, "name must be at most 100 characters")
        XCTAssertEqual(refreshed, 0)
    }

    func testBadRequestWithoutMessageFallsBack() async {
        let model = make(outcome: { .rejected(nil) }, calls: Calls())
        model.name = "x"
        await model.create()
        XCTAssertEqual(model.error?.message, "That didn't look right.")
    }

    func testNetworkErrorShowsTransportMessage() async {
        let model = make(outcome: { throw URLError(.timedOut) }, calls: Calls())
        model.name = "x"
        await model.create()
        XCTAssertEqual(model.error, .transport)
    }
}
