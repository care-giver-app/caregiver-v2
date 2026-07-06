import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class TrackerSummariesTests: XCTestCase {

    // MARK: helpers

    private func field(_ key: String, _ type: Components.Schemas.FieldType,
                       unit: String? = nil, options: [String]? = nil) -> Components.Schemas.Field {
        .init(key: key, label: key, _type: type, unit: unit, options: options)
    }

    private func tracker(kind: Components.Schemas.TrackerKind,
                         fields: [Components.Schemas.Field] = [],
                         name: String = "T",
                         archived: Bool = false) -> Components.Schemas.Tracker {
        .init(trackerId: UUID().uuidString, receiverId: "r1", careGroupId: "g1",
              name: name, kind: kind, fields: fields,
              createdBy: "u1", createdAt: Date(), archived: archived)
    }

    private func summary(_ t: Components.Schemas.Tracker, lastAt: Date?) -> TrackerSummary {
        let event = lastAt.map {
            Components.Schemas.Event(
                trackerId: t.trackerId, eventId: UUID().uuidString, careGroupId: "g1", receiverId: "r1",
                values: .init(additionalProperties: try! OpenAPIObjectContainer(unvalidatedValue: [:])),
                occurredAt: $0, loggedBy: "u1", createdAt: $0)
        }
        return TrackerSummary(tracker: t, lastEvent: event)
    }

    // MARK: kind label (sample-data.md mapping table)

    func testKindLabelChecklistForScheduled() {
        XCTAssertEqual(TrackerSummariesModel.kindLabel(kind: .scheduled, fields: []), "Checklist")
    }

    func testKindLabelQuickLogForEventWithNoFields() {
        XCTAssertEqual(TrackerSummariesModel.kindLabel(kind: .event, fields: []), "Quick log")
    }

    func testKindLabelScaleForEnumField() {
        let fields = [field("mood", ._enum, options: ["Good", "Okay", "Bad"])]
        XCTAssertEqual(TrackerSummariesModel.kindLabel(kind: .event, fields: fields), "Scale")
    }

    func testKindLabelDurationForTimeUnitNumber() {
        XCTAssertEqual(
            TrackerSummariesModel.kindLabel(kind: .event, fields: [field("slept", .number, unit: "h")]),
            "Duration")
        XCTAssertEqual(
            TrackerSummariesModel.kindLabel(kind: .measurement, fields: [field("nap", .number, unit: "minutes")]),
            "Duration")
    }

    func testKindLabelNumericForMeasurementNumber() {
        let fields = [field("systolic", .number, unit: "mmHg")]
        XCTAssertEqual(TrackerSummariesModel.kindLabel(kind: .measurement, fields: fields), "Numeric")
    }

    func testKindLabelCountForEventWithFields() {
        XCTAssertEqual(
            TrackerSummariesModel.kindLabel(kind: .event, fields: [field("what", .text)]),
            "Count")
    }

    // MARK: recency (home.md decision 8 — fresh <24h, NEVER overdue)

    func testRecencyFreshWithin24Hours() {
        let now = Date()
        let s = summary(tracker(kind: .event), lastAt: now.addingTimeInterval(-2 * 3600))
        XCTAssertEqual(s.recency(now: now), .fresh)
    }

    func testRecencyNormalBeyond24Hours() {
        let now = Date()
        let s = summary(tracker(kind: .event), lastAt: now.addingTimeInterval(-25 * 3600))
        XCTAssertEqual(s.recency(now: now), .normal)
    }

    func testRecencyNormalWhenNeverLogged() {
        let s = summary(tracker(kind: .event), lastAt: nil)
        XCTAssertEqual(s.recency(now: Date()), .normal)
    }

    // MARK: needs attention (trackers.md decision 6 — never-logged or 7+ days)

    func testNeedsAttentionWhenNeverLogged() {
        XCTAssertTrue(summary(tracker(kind: .event), lastAt: nil).needsAttention(now: Date()))
    }

    func testNeedsAttentionAfterSevenDays() {
        let now = Date()
        XCTAssertTrue(summary(tracker(kind: .event),
                              lastAt: now.addingTimeInterval(-8 * 86400)).needsAttention(now: now))
        XCTAssertFalse(summary(tracker(kind: .event),
                               lastAt: now.addingTimeInterval(-6 * 86400)).needsAttention(now: now))
    }

    // MARK: recency text

    func testRecencyTextBuckets() {
        let now = Date()
        let t = tracker(kind: .event)
        XCTAssertEqual(summary(t, lastAt: now.addingTimeInterval(-30 * 60)).recencyText(now: now), "30m ago")
        XCTAssertEqual(summary(t, lastAt: now.addingTimeInterval(-2 * 3600)).recencyText(now: now), "2h ago")
        XCTAssertEqual(summary(t, lastAt: now.addingTimeInterval(-3 * 86400)).recencyText(now: now), "3d ago")
        XCTAssertNil(summary(t, lastAt: nil).recencyText(now: now))
    }

    func testRecencyTextYesterday() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let yesterday = calendar.date(byAdding: .hour, value: -20, to: now)!  // <24h but prior day
        XCTAssertEqual(summary(tracker(kind: .event), lastAt: yesterday)
            .recencyText(now: now, calendar: calendar), "Yesterday")
    }

    // MARK: attention-first ordering (home.md snapshot)

    func testAttentionFirstOrdering() {
        let now = Date()
        let fresh = summary(tracker(kind: .event, name: "Fresh"), lastAt: now.addingTimeInterval(-3600))
        let stale = summary(tracker(kind: .event, name: "Stale"), lastAt: now.addingTimeInterval(-3 * 86400))
        let silent = summary(tracker(kind: .event, name: "Silent"), lastAt: now.addingTimeInterval(-9 * 86400))
        let never = summary(tracker(kind: .event, name: "Never"), lastAt: nil)
        let sorted = TrackerSummariesModel.attentionFirst([fresh, stale, silent, never], now: now)
        // Attention group first (never-logged before oldest-logged), then the rest, stalest first.
        XCTAssertEqual(sorted.map(\.tracker.name), ["Never", "Silent", "Stale", "Fresh"])
    }
}
