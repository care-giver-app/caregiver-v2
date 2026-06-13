import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Supplies the current Cognito ID token (nil when signed out).
protocol TokenProvider: Sendable {
    func idToken() async throws -> String?
}

/// Stamps `Authorization: Bearer <id-token>` on every outgoing request.
struct AuthMiddleware: ClientMiddleware {
    let tokenProvider: TokenProvider

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = try await tokenProvider.idToken() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}
