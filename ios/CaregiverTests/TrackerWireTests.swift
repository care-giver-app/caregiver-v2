import XCTest
import HTTPTypes
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

/// The tracker and schedule writes as they go over the wire: the live `TrackersService`
/// on the client `APIClient.make` builds, with a transport that keeps each request and
/// answers 500. Checks the JSON the generated client and our middlewares actually send.
final class TrackerWireTests: XCTestCase {
    private struct NoToken: TokenProvider {
        func idToken() async throws -> String? { nil }
    }

    /// Keeps every request it is handed; answers each with a 500 and no body.
    private actor CapturingTransport: ClientTransport {
        private(set) var sent: [(operationID: String, request: HTTPRequest, body: Data?)] = []

        func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
                  operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
            let data: Data? = if let body { try await Data(collecting: body, upTo: 1 << 20) } else { nil }
            sent.append((operationID, request, data))
            return (HTTPResponse(status: .internalServerError), nil)
        }
    }

    private func service(_ transport: CapturingTransport) -> TrackersService {
        .live(APIClient.make(tokenProvider: NoToken(), serverURL: URL(string: "https://api.example")!,
                             transport: transport))
    }

    private func sentJSON(_ transport: CapturingTransport) async throws -> (String, [String: Any]) {
        let sent = await transport.sent
        let last = try XCTUnwrap(sent.last)
        let body = try XCTUnwrap(last.body)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return (last.operationID, object)
    }

    private let weight = TrackerWrite(name: "Weight", icon: "scalemass", color: "#4F8EF7", fields: [
        FieldWrite(fieldID: "w", label: "Weight", kind: .number, unit: "lb", required: true,
                   range: ValueRangeInfo(low: 80.5, high: 400)),
    ], gapHours: nil)

    // MARK: Edit tracker

    func testEditWithTheGapOffSendsAnExplicitNull() async throws {
        let transport = CapturingTransport()
        _ = try? await service(transport).editTracker("t1", weight, false)
        let (op, json) = try await sentJSON(transport)
        XCTAssertEqual(op, "editTracker")
        XCTAssertTrue(json.keys.contains("gap_hours"), "the server requires the key")
        XCTAssertTrue(json["gap_hours"] is NSNull)
        XCTAssertEqual(json["name"] as? String, "Weight")
        XCTAssertNil(json["remove_schedules"], "left out until the admin confirms")
        let fields = try XCTUnwrap(json["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.first?["field_id"] as? String, "w")
        let range = try XCTUnwrap(fields.first?["range"] as? [String: Any])
        XCTAssertEqual(range["low"] as? Double, 80.5)
    }

    func testEditWithAGapSendsItsHours() async throws {
        let transport = CapturingTransport()
        var write = weight
        write.gapHours = 168
        _ = try? await service(transport).editTracker("t1", write, true)
        let (op, json) = try await sentJSON(transport)
        XCTAssertEqual(op, "editTracker")
        XCTAssertEqual(json["gap_hours"] as? Int, 168)
        XCTAssertEqual(json["remove_schedules"] as? Bool, true)
    }

    func testTheNullIsAddedOnlyWhenTheKeyIsMissing() throws {
        let missing = Data(#"{"name":"A"}"#.utf8)
        XCTAssertEqual(GapHoursNullMiddleware.addingNullGap(to: missing).map { String(decoding: $0, as: UTF8.self) },
                       #"{"gap_hours":null,"name":"A"}"#)
        XCTAssertEqual(GapHoursNullMiddleware.addingNullGap(to: Data("{ }".utf8))
                           .map { String(decoding: $0, as: UTF8.self) },
                       #"{"gap_hours":null }"#)
        XCTAssertNil(GapHoursNullMiddleware.addingNullGap(to: Data(#"{"gap_hours":3}"#.utf8)))
        XCTAssertNil(GapHoursNullMiddleware.addingNullGap(to: Data(#"{"gap_hours":null}"#.utf8)))
        XCTAssertNil(GapHoursNullMiddleware.addingNullGap(to: Data("[1]".utf8)))
    }

    // MARK: Add tracker, Add a schedule

    func testAddTrackerSendsTheTracker() async throws {
        let transport = CapturingTransport()
        _ = try? await service(transport).addTracker("r1", weight)
        let (op, json) = try await sentJSON(transport)
        XCTAssertEqual(op, "addTracker")
        XCTAssertEqual(json["name"] as? String, "Weight")
        XCTAssertEqual(json["icon"] as? String, "scalemass")
        XCTAssertFalse(json.keys.contains("gap_hours"), "Add tracker leaves a gap that is off out")
        XCTAssertEqual((json["fields"] as? [[String: Any]])?.count, 1)
    }

    func testAddScheduleSendsTheRuleAndPrefills() async throws {
        let transport = CapturingTransport()
        let write = ScheduleWrite(label: nil, days: [.mo, .we], interval: 2, time: "08:00", endsOn: nil,
                                  plannedValues: ["mg": .number(12.5)], unrecordedAlert: true)
        _ = try? await service(transport).addSchedule("t1", write, true)
        let (op, json) = try await sentJSON(transport)
        XCTAssertEqual(op, "addSchedule")
        XCTAssertEqual(json["time"] as? String, "08:00")
        let rule = try XCTUnwrap(json["rule"] as? [String: Any])
        XCTAssertEqual(rule["interval"] as? Int, 2)
        XCTAssertEqual(rule["by_day"] as? [String], ["MO", "WE"])
        XCTAssertEqual(json["replace_gap"] as? Bool, true)
        XCTAssertFalse(json.keys.contains("gap_hours"), "only Edit tracker gets the explicit null")
        let planned = try XCTUnwrap(json["planned_values"] as? [String: Any])
        XCTAssertEqual(planned["mg"] as? Double, 12.5)
    }
}
