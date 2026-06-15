import Foundation
import OpenAPIRuntime

/// Decodes/encodes RFC3339 timestamps with OR without fractional seconds.
///
/// The API emits fractional seconds for raw `time.Time` fields (receivers,
/// trackers, events serialize the domain entity directly → Go's RFC3339Nano),
/// but whole seconds for `getMe` (which hand-formats `time.RFC3339`). swift-openapi's
/// default `.iso8601` transcoder uses a plain `ISO8601DateFormatter`, which *rejects*
/// fractional seconds — so it can't decode receiver/tracker/event responses. A formatter
/// with `.withFractionalSeconds` would conversely reject the whole-second strings, so we
/// must try both. Both forms are valid RFC3339.
struct FlexibleISO8601DateTranscoder: DateTranscoder {
    func encode(_ date: Date) throws -> String {
        formatter(fractional: true).string(from: date)
    }

    func decode(_ string: String) throws -> Date {
        if let date = formatter(fractional: true).date(from: string) { return date }
        if let date = formatter(fractional: false).date(from: string) { return date }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Expected an RFC3339 date string, got \(string).")
        )
    }

    /// A fresh formatter per call — `ISO8601DateFormatter` is cheap enough at this
    /// app's volume and avoids sharing mutable formatter state across threads.
    private func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }
}
