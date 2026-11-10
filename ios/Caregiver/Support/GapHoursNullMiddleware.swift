import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sends Edit tracker's `gap_hours` as an explicit `null` when the gap is off.
///
/// The contract says `TrackerChanges.gap_hours` is required and `null` turns the gap off
/// (`api/internal/v1/trackers.go` refuses a body without the key). The generated Swift
/// type holds it as `Int?`, and its synthesized `Codable` leaves a nil out of the JSON
/// entirely — so without this, every Save on a tracker with no gap would be refused.
/// For `editTracker` only, and only when the key is missing, this writes
/// `"gap_hours":null,` just inside the body's opening brace; everything else is sent
/// exactly as encoded.
struct GapHoursNullMiddleware: ClientMiddleware {
    static let operationID = "editTracker"
    /// Far beyond any Edit tracker body; a bigger one is passed on untouched.
    static let maxBody = 1 << 20

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == Self.operationID, let body else {
            return try await next(request, body, baseURL)
        }
        let data = try await Data(collecting: body, upTo: Self.maxBody)
        guard let patched = Self.addingNullGap(to: data) else {
            return try await next(request, HTTPBody(data), baseURL)
        }
        var request = request
        if request.headerFields[.contentLength] != nil {
            request.headerFields[.contentLength] = String(patched.count)
        }
        return try await next(request, HTTPBody(patched), baseURL)
    }

    /// The body with `"gap_hours":null` added, or nil when it already has the key or
    /// isn't a JSON object.
    static func addingNullGap(to data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["gap_hours"] == nil,
              let brace = data.firstIndex(where: { !Self.isWhitespace($0) }),
              data[brace] == UInt8(ascii: "{")
        else { return nil }
        let key = Data((object.isEmpty ? #""gap_hours":null"# : #""gap_hours":null,"#).utf8)
        var out = data
        out.insert(contentsOf: key, at: data.index(after: brace))
        return out
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }
}
