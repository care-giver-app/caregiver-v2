import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class TrackerFilterTests: XCTestCase {
    private func summary(name: String, lastAt: Date?, archived: Bool = false) -> TrackerSummary {
        let t = Components.Schemas.Tracker(
            trackerId: UUID().uuidString, receiverId: "r1", careGroupId: "g1",
            name: name, kind: .event, fields: [],
            createdBy: "u1", createdAt: Date(), archived: archived)
        let e = lastAt.map {
            Components.Schemas.Event(
                trackerId: t.trackerId, eventId: UUID().uuidString, careGroupId: "g1", receiverId: "r1",
                values: .init(additionalProperties: try! OpenAPIObjectContainer(unvalidatedValue: [:])),
                occurredAt: $0, loggedBy: "u1", createdAt: $0)
        }
        return TrackerSummary(tracker: t, lastEvent: e)
    }

    func testAllReturnsActiveOnly() {
        let now = Date()
        let active = [summary(name: "A", lastAt: now)]
        let archived = [summary(name: "Z", lastAt: nil, archived: true)]
        XCTAssertEqual(
            TrackerFilter.all.apply(active: active, archived: archived, now: now).map(\.tracker.name),
            ["A"])
    }

    func testNeedsAttentionFiltersQuietTrackers() {
        let now = Date()
        let fresh = summary(name: "Fresh", lastAt: now.addingTimeInterval(-3600))
        let silent = summary(name: "Silent", lastAt: now.addingTimeInterval(-8 * 86400))
        let never = summary(name: "Never", lastAt: nil)
        let result = TrackerFilter.needsAttention
            .apply(active: [fresh, silent, never], archived: [], now: now)
        XCTAssertEqual(Set(result.map(\.tracker.name)), ["Silent", "Never"])
    }

    func testArchivedReturnsArchivedOnly() {
        let archived = [summary(name: "Old", lastAt: nil, archived: true)]
        XCTAssertEqual(
            TrackerFilter.archived.apply(active: [], archived: archived, now: Date()).map(\.tracker.name),
            ["Old"])
    }
}
