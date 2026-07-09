import XCTest
import CaregiverAPI
@testable import Caregiver

final class AddTrackerTests: XCTestCase {
    // MARK: Fixtures

    private func field(
        _ key: String, _ label: String, type: Components.Schemas.FieldType = .number,
        unit: String? = nil, required: Bool = false,
        threshold: Components.Schemas.Threshold? = nil
    ) -> Components.Schemas.Field {
        .init(key: key, label: label, _type: type, unit: unit, required: required, threshold: threshold)
    }

    private func bloodPressure() -> Components.Schemas.TrackerTemplate {
        .init(
            templateId: "blood_pressure", name: "Blood Pressure", kind: .measurement,
            icon: "heart", color: "#E5484D",
            fields: [
                field("systolic", "Systolic", unit: "mmHg", required: true, threshold: .init(max: 140)),
                field("diastolic", "Diastolic", unit: "mmHg", required: true, threshold: .init(max: 90)),
                field("pulse", "Pulse", unit: "bpm", required: false),
            ]
        )
    }

    private func threshold(in write: Components.Schemas.TrackerWrite, key: String) -> Components.Schemas.Threshold? {
        write.fields.first { $0.key == key }?.threshold
    }

    // MARK: Hue map

    func testHueMapForKnownTemplates() {
        XCTAssertEqual(AddTrackerLogic.hue(forTemplateID: "blood_pressure"), .cyan)
        XCTAssertEqual(AddTrackerLogic.hue(forTemplateID: "weight"), .teal)
        XCTAssertEqual(AddTrackerLogic.hue(forTemplateID: "medication"), .violet)
        XCTAssertEqual(AddTrackerLogic.hue(forTemplateID: "temperature"), .infoBlue)
    }

    func testHueMapFallsBackToCyanForUnknown() {
        XCTAssertEqual(AddTrackerLogic.hue(forTemplateID: "totally_new"), .cyan)
    }

    func testHueHexValues() {
        XCTAssertEqual(TrackerHue.cyan.hex, "4dd6e6")
        XCTAssertEqual(TrackerHue.infoBlue.hex, "93C5FD")
    }

    // MARK: Kind label (raw contract kind, decision 10)

    func testKindLabel() {
        XCTAssertEqual(AddTrackerLogic.kindLabel(.event), "Event")
        XCTAssertEqual(AddTrackerLogic.kindLabel(.measurement), "Measurement")
        XCTAssertEqual(AddTrackerLogic.kindLabel(.scheduled), "Scheduled")
    }

    // MARK: makeWrite — name / color / kind / icon

    func testMakeWriteTrimsNameAndAppliesColorKeepingKindAndIcon() {
        let write = AddTrackerLogic.makeWrite(
            template: bloodPressure(), name: "  Morning BP  ",
            colorHex: "4dd6e6", thresholds: [:]
        )
        XCTAssertEqual(write.name, "Morning BP")
        XCTAssertEqual(write.color, "4dd6e6")
        XCTAssertEqual(write.kind, .measurement)
        XCTAssertEqual(write.icon, "heart")
        XCTAssertEqual(write.fields.count, 3)
    }

    // MARK: makeWrite — per-field threshold binding (decision 8/13)

    func testEditedThresholdBindsToTheRightField() {
        let write = AddTrackerLogic.makeWrite(
            template: bloodPressure(), name: "BP", colorHex: "4dd6e6",
            thresholds: [
                "systolic": .init(min: "", max: "150"),
                "pulse": .init(min: "40", max: "120"),
            ]
        )
        XCTAssertNil(threshold(in: write, key: "systolic")?.min)
        XCTAssertEqual(threshold(in: write, key: "systolic")?.max, 150)
        XCTAssertEqual(threshold(in: write, key: "pulse")?.min, 40)
        XCTAssertEqual(threshold(in: write, key: "pulse")?.max, 120)
    }

    func testUneditedFieldKeepsTemplateThreshold() {
        let write = AddTrackerLogic.makeWrite(
            template: bloodPressure(), name: "BP", colorHex: "4dd6e6",
            thresholds: ["systolic": .init(min: "", max: "150")]
        )
        // diastolic was not in the edit dict → template threshold preserved.
        XCTAssertEqual(threshold(in: write, key: "diastolic")?.max, 90)
    }

    func testBlankBothBoundsDropsThreshold() {
        let write = AddTrackerLogic.makeWrite(
            template: bloodPressure(), name: "BP", colorHex: "4dd6e6",
            thresholds: ["systolic": .init(min: "  ", max: "")]
        )
        XCTAssertNil(threshold(in: write, key: "systolic"))
    }

    func testInvalidThresholdTextParsesAsNoLimit() {
        let write = AddTrackerLogic.makeWrite(
            template: bloodPressure(), name: "BP", colorHex: "4dd6e6",
            thresholds: ["systolic": .init(min: "abc", max: "130")]
        )
        XCTAssertNil(threshold(in: write, key: "systolic")?.min)
        XCTAssertEqual(threshold(in: write, key: "systolic")?.max, 130)
    }
}
