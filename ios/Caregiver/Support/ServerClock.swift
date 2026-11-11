import Foundation
import HTTPTypes
import OpenAPIRuntime

/// The phone's clock corrected to the server's. The server refuses a time more than a
/// minute ahead of its own clock (`ClockSkew`), so a phone running fast could never log
/// "now"; writes that send now, and checks that a time is not in the future, use this.
///
/// The offset is estimated from the `Date` header of each API response (whole seconds,
/// so it is good to about a second). Until a response carries one it is zero.
final class ServerClock: @unchecked Sendable {
    /// The one the app's API client feeds.
    static let shared = ServerClock()

    private let lock = NSLock()
    private var _offset: TimeInterval = 0
    private let local: @Sendable () -> Date

    init(local: @escaping @Sendable () -> Date = Date.init) {
        self.local = local
    }

    /// Server time minus phone time, as last seen.
    var offset: TimeInterval { lock.withLock { _offset } }

    /// Now, by the server's clock.
    func now() -> Date { local().addingTimeInterval(offset) }

    /// A response said the server's time was `serverDate`; the phone's is read now.
    func record(serverDate: Date) {
        let offset = serverDate.timeIntervalSince(local())
        lock.withLock { _offset = offset }
    }

    /// An HTTP `Date` header (RFC 9110 IMF-fixdate: "Sun, 06 Nov 1994 08:49:37 GMT").
    static func parseHTTPDate(_ s: String) -> Date? {
        httpDate.date(from: s)
    }

    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}

/// Feeds `ServerClock` the `Date` header of every response. A response without one, or
/// with one that does not parse, leaves the offset as it was.
struct ServerClockMiddleware: ClientMiddleware {
    let clock: ServerClock

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        if let header = response.headerFields[.date], let date = ServerClock.parseHTTPDate(header) {
            clock.record(serverDate: date)
        }
        return (response, responseBody)
    }
}
