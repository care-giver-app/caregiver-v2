import Foundation
import CaregiverAPI
import OpenAPIURLSession

enum APIClient {
    /// Builds a CaregiverAPI client pointed at the configured base URL, with the
    /// auth middleware that stamps the bearer token on every request.
    static func make(tokenProvider: TokenProvider) -> Client {
        Client(
            serverURL: AppConfig.baseURL,
            transport: URLSessionTransport(),
            middlewares: [AuthMiddleware(tokenProvider: tokenProvider)]
        )
    }
}
