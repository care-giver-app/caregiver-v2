import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class ScheduleModelTests: XCTestCase {
    private func tracker(_ id: String, name: String = "T", archived: Bool = false) -> Components.Schemas.Tracker {
        .init(
            trackerId: id, receiverId: "r", careGroupId: "g",
            name: name, kind: .scheduled, fields: [],
            createdBy: "u", createdAt: Date(timeIntervalSince1970: 0), archived: archived
        )
    }

    private func item(_ id: String, tracker: String, at seconds: TimeInterval, note: String? = nil) -> Components.Schemas.ScheduledItem {
        .init(
            scheduledItemId: id, trackerId: tracker, careGroupId: "g", receiverId: "r",
            values: .init(additionalProperties: try! OpenAPIObjectContainer(unvalidatedValue: [:])),
            note: note, scheduledFor: Date(timeIntervalSince1970: seconds),
            createdBy: "u", createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testMapPreservesServerOrderAndJoinsTrackerName() {
        let trackers = [tracker("t1", name: "Cardiology"), tracker("t2", name: "Physical therapy")]
        // server returns soonest-first; map must not resort
        let items = [item("s1", tracker: "t2", at: 100), item("s2", tracker: "t1", at: 200)]
        let mapped = ScheduleModel.map(items: items, trackers: trackers)
        XCTAssertEqual(mapped.map { $0.id }, ["s1", "s2"])
        XCTAssertEqual(mapped.map { $0.name }, ["Physical therapy", "Cardiology"])
    }

    func testMapDropsMissingAndArchivedTrackers() {
        let trackers = [tracker("t1"), tracker("t2", archived: true)]
        let items = [
            item("s1", tracker: "t1", at: 100),   // kept
            item("s2", tracker: "t2", at: 200),   // dropped: archived tracker
            item("s3", tracker: "tX", at: 300),   // dropped: no such tracker
        ]
        XCTAssertEqual(ScheduleModel.map(items: items, trackers: trackers).map { $0.id }, ["s1"])
    }

    func testSubtitleUsesNoteWhenPresent() {
        let mapped = ScheduleModel.map(
            items: [item("s1", tracker: "t1", at: 100, note: "Riverside Clinic")],
            trackers: [tracker("t1")]
        )
        XCTAssertEqual(mapped.first?.subtitle, "Riverside Clinic")
    }

    func testSubtitleNilWhenNoteBlankOrAbsent() {
        let blank = ScheduleModel.map(items: [item("s1", tracker: "t1", at: 100, note: "   ")], trackers: [tracker("t1")])
        XCTAssertNil(blank.first?.subtitle)
        let absent = ScheduleModel.map(items: [item("s2", tracker: "t1", at: 100)], trackers: [tracker("t1")])
        XCTAssertNil(absent.first?.subtitle)
    }
}
