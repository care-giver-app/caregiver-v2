import Foundation
import CaregiverAPI
import OpenAPIRuntime
import OpenAPIURLSession

enum APIClient {
    /// Builds a CaregiverAPI client pointed at the configured base URL, with the
    /// auth middleware that stamps the bearer token on every request and the one that
    /// sends Edit tracker's `gap_hours` as an explicit null, and the one that reads the
    /// server's clock off every response for `serverClock`. Tests pass their own
    /// `transport` to see exactly what would go over the wire.
    static func make(tokenProvider: TokenProvider,
                     serverURL: URL = AppConfig.baseURL,
                     transport: ClientTransport = URLSessionTransport(),
                     serverClock: ServerClock = .shared) -> Client {
        // The API emits RFC3339 timestamps with fractional seconds for some fields
        // and without for others; the default .iso8601 transcoder rejects fractional
        // seconds, so use one that accepts both.
        var configuration = Configuration()
        configuration.dateTranscoder = FlexibleISO8601DateTranscoder()
        return Client(
            serverURL: serverURL,
            configuration: configuration,
            transport: transport,
            middlewares: [AuthMiddleware(tokenProvider: tokenProvider), GapHoursNullMiddleware(),
                          ServerClockMiddleware(clock: serverClock)]
        )
    }
}
