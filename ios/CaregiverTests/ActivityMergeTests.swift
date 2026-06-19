import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class ActivityMergeTests: XCTestCase {
    private func tracker(_ id: String) -> Components.Schemas.Tracker {
        .init(
            trackerId: id, receiverId: "r", careGroupId: "g",
            name: "T-\(id)", kind: .measurement, fields: [],
            createdBy: "u", createdAt: Date(timeIntervalSince1970: 0), archived: false
        )
    }

    private func event(_ id: String, at seconds: TimeInterval) -> Components.Schemas.Event {
        .init(
            trackerId: "t", eventId: id, careGroupId: "g", receiverId: "r",
            values: .init(additionalProperties: try! OpenAPIObjectContainer(unvalidatedValue: [:])),
            occurredAt: Date(timeIntervalSince1970: seconds),
            loggedBy: "u", createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testMergeSortsNewestFirstAcrossTrackers() {
        let t1 = tracker("1"); let t2 = tracker("2")
        let input: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = [
            (t1, [event("a", at: 100), event("b", at: 300)]),
            (t2, [event("c", at: 200)]),
        ]
        let refs = ActivityModel.merge(input)
        XCTAssertEqual(refs.map { $0.event.eventId }, ["b", "c", "a"])
    }

    func testMergeEmptyInputIsEmpty() {
        XCTAssertTrue(ActivityModel.merge([]).isEmpty)
    }

    func testMergeTieBreaksDeterministicallyByEventId() {
        let t1 = tracker("1")
        let input: [(Components.Schemas.Tracker, [Components.Schemas.Event])] = [
            (t1, [event("y", at: 100), event("x", at: 100)]),
        ]
        // Equal timestamps → stable, deterministic order by eventId ascending.
        XCTAssertEqual(ActivityModel.merge(input).map { $0.event.eventId }, ["x", "y"])
    }
}
