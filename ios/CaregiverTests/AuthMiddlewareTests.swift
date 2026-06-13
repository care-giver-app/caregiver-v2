import XCTest
import HTTPTypes
import OpenAPIRuntime
@testable import Caregiver

private struct FakeTokenProvider: TokenProvider {
    let token: String?
    func idToken() async throws -> String? { token }
}

/// Captures a value from inside the @Sendable `next` closure. Access is serial
/// (the closure runs to completion before `intercept` returns), so unchecked
/// Sendable is safe here.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class AuthMiddlewareTests: XCTestCase {
    func testStampsBearerWhenTokenPresent() async throws {
        let mw = AuthMiddleware(tokenProvider: FakeTokenProvider(token: "abc.def.ghi"))
        let seen = Box<HTTPRequest?>(nil)
        let req = HTTPRequest(method: .get, scheme: "https", authority: "x", path: "/me")
        _ = try await mw.intercept(req, body: nil, baseURL: URL(string: "https://x")!, operationID: "getMe") { r, _, _ in
            seen.value = r
            return (HTTPResponse(status: .ok), nil)
        }
        XCTAssertEqual(seen.value?.headerFields[.authorization], "Bearer abc.def.ghi")
    }

    func testNoHeaderWhenTokenNil() async throws {
        let mw = AuthMiddleware(tokenProvider: FakeTokenProvider(token: nil))
        let seen = Box<HTTPRequest?>(nil)
        let req = HTTPRequest(method: .get, scheme: "https", authority: "x", path: "/me")
        _ = try await mw.intercept(req, body: nil, baseURL: URL(string: "https://x")!, operationID: "getMe") { r, _, _ in
            seen.value = r
            return (HTTPResponse(status: .ok), nil)
        }
        XCTAssertNil(seen.value?.headerFields[.authorization])
    }
}
