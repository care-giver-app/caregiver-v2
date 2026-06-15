import Foundation
import CaregiverAPI
import OpenAPIRuntime
import OpenAPIURLSession

enum APIClient {
    /// Builds a CaregiverAPI client pointed at the configured base URL, with the
    /// auth middleware that stamps the bearer token on every request.
    static func make(tokenProvider: TokenProvider) -> Client {
        // The API emits RFC3339 timestamps with fractional seconds for some fields
        // and without for others; the default .iso8601 transcoder rejects fractional
        // seconds, so use one that accepts both.
        var configuration = Configuration()
        configuration.dateTranscoder = FlexibleISO8601DateTranscoder()
        return Client(
            serverURL: AppConfig.baseURL,
            configuration: configuration,
            transport: URLSessionTransport(),
            middlewares: [AuthMiddleware(tokenProvider: tokenProvider)]
        )
    }
}
