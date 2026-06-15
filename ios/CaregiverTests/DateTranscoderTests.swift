import XCTest
import Foundation
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

/// Regression for the C1 decode bug: the Go API emits RFC3339Nano (fractional
/// seconds) for raw time.Time fields (receivers/trackers/events), but getMe
/// hand-formats time.RFC3339 (whole seconds). The client must accept BOTH.
final class DateTranscoderTests: XCTestCase {
    private let transcoder = FlexibleISO8601DateTranscoder()

    func testDecodesFractionalSeconds() throws {
        let frac = try transcoder.decode("2026-06-15T16:53:06.500Z")
        let whole = try transcoder.decode("2026-06-15T16:53:06Z")
        XCTAssertEqual(frac.timeIntervalSince(whole), 0.5, accuracy: 0.01)
    }

    func testDecodesWholeSeconds() throws {
        _ = try transcoder.decode("2026-06-15T16:53:06Z") // getMe's format — must not throw
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try transcoder.decode("not-a-date"))
    }

    func testDefaultTranscoderRejectsFractional() {
        // Documents the root cause: the default .iso8601 transcoder (which the
        // client used) cannot parse the fractional-seconds the API emits.
        XCTAssertThrowsError(try ISO8601DateTranscoder().decode("2026-06-15T16:53:06.500Z"))
    }

    func testDecodesReceiverWithFractionalCreatedAt() throws {
        // The exact shape createReceiver/listReceivers return (archived present, fractional created_at).
        let json = Data("""
        {"receiver_id":"r1","care_group_id":"g1","name":"Charlie","created_by":"u1","created_at":"2026-06-15T16:53:06.123456Z","archived":false}
        """.utf8)
        let decoder = JSONDecoder()
        let t = transcoder
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            return try t.decode(s)
        }
        let receiver = try decoder.decode(Components.Schemas.Receiver.self, from: json)
        XCTAssertEqual(receiver.name, "Charlie")
        XCTAssertFalse(receiver.archived)
    }
}
