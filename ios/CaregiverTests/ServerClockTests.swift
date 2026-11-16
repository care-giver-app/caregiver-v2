import XCTest
import HTTPTypes
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

/// The server's clock as read off each response's `Date` header, and Home's writes as
/// they come back over the wire: the live `HomeService` on the client `APIClient.make`
/// builds, with a transport that answers as each test says.
final class ServerClockTests: XCTestCase {
    private struct NoToken: TokenProvider {
        func idToken() async throws -> String? { nil }
    }

    /// Answers every request with `response`, or throws `error`.
    private struct StubTransport: ClientTransport {
        var response = HTTPResponse(status: .internalServerError)
        var body: String?
        var error: (any Error)?

        func send(_ request: HTTPRequest, body _: HTTPBody?, baseURL: URL,
                  operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
            if let error { throw error }
            return (response, body.map { HTTPBody($0) })
        }
    }

    /// The phone's clock, fixed: Sun Nov 8 2026, 00:00:00 UTC.
    private static let phoneNow = ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z")!

    private func client(_ transport: StubTransport, clock: ServerClock) -> Client {
        APIClient.make(tokenProvider: NoToken(), serverURL: URL(string: "https://api.example")!,
                       transport: transport, serverClock: clock)
    }

    private func response(date: String?, status: HTTPResponse.Status = .internalServerError) -> HTTPResponse {
        var r = HTTPResponse(status: status)
        if let date { r.headerFields[.date] = date }
        r.headerFields[.contentType] = "application/json"
        return r
    }

    // MARK: The server's clock

    func testParsesAnHTTPDate() {
        XCTAssertEqual(ServerClock.parseHTTPDate("Sun, 08 Nov 2026 00:00:00 GMT"), Self.phoneNow)
        XCTAssertNil(ServerClock.parseHTTPDate("yesterday"))
    }

    func testEveryResponsesDateSetsTheOffset() async throws {
        let clock = ServerClock(local: { Self.phoneNow })
        XCTAssertEqual(clock.offset, 0)
        XCTAssertEqual(clock.now(), Self.phoneNow)

        // The phone runs five minutes fast: the server says 23:55.
        let home = HomeService.live(client(StubTransport(response: response(date: "Sat, 07 Nov 2026 23:55:00 GMT")),
                                           clock: clock))
        _ = try? await home.waiting("r1")
        XCTAssertEqual(clock.offset, -300)
        XCTAssertEqual(clock.now(), Self.phoneNow.addingTimeInterval(-300))
    }

    func testAResponseWithoutADateLeavesTheOffset() async throws {
        let clock = ServerClock(local: { Self.phoneNow })
        let home = HomeService.live(client(StubTransport(response: response(date: nil)), clock: clock))
        _ = try? await home.waiting("r1")
        XCTAssertEqual(clock.offset, 0)

        clock.record(serverDate: Self.phoneNow.addingTimeInterval(42))
        let garbled = HomeService.live(client(StubTransport(response: response(date: "soon")), clock: clock))
        _ = try? await garbled.waiting("r1")
        XCTAssertEqual(clock.offset, 42)
    }

    // MARK: Home's writes over the wire

    func testA409IsEntryNotInStateAndA400CarriesTheServersMessage() async {
        let conflict = HomeService.live(client(StubTransport(
            response: response(date: nil, status: .conflict), body: #"{"message":"the tracker is paused"}"#),
            clock: ServerClock()))
        do {
            _ = try await conflict.addEntry("bp", NewEntryWrite(at: nil, values: [:]))
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? EntryNotInState, EntryNotInState(message: "the tracker is paused"))
        }

        let bad = HomeService.live(client(StubTransport(
            response: response(date: nil, status: .badRequest), body: #"{"message":"Systolic is required"}"#),
            clock: ServerClock()))
        do {
            _ = try await bad.addJournalNote("r1", NoteWrite(at: Self.phoneNow, body: "x"))
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? AppError, AppError.forStatus(400, serverMessage: "Systolic is required"))
            XCTAssertFalse(QuickLogModel.mayHaveLanded(error))
        }
    }

    func testAServerErrorDidNotLandButATimeoutMayHave() async {
        let failing = HomeService.live(client(StubTransport(response: response(date: nil, status: .badGateway)),
                                              clock: ServerClock()))
        do {
            _ = try await failing.addEntry("bp", NewEntryWrite(at: nil, values: [:]))
            XCTFail("expected a failure")
        } catch {
            XCTAssertFalse(QuickLogModel.mayHaveLanded(error))
        }

        // The generated client wraps the transport's error.
        let lost = HomeService.live(client(StubTransport(error: URLError(.timedOut)), clock: ServerClock()))
        do {
            _ = try await lost.addEntry("bp", NewEntryWrite(at: nil, values: [:]))
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(error is ClientError)
            XCTAssertTrue(QuickLogModel.mayHaveLanded(error))
        }

        let offline = HomeService.live(client(StubTransport(error: URLError(.notConnectedToInternet)),
                                              clock: ServerClock()))
        do {
            _ = try await offline.addJournalNote("r1", NoteWrite(at: Self.phoneNow, body: "x"))
            XCTFail("expected a failure")
        } catch {
            XCTAssertFalse(QuickLogModel.mayHaveLanded(error))
        }
    }
}
