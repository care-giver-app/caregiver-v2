import XCTest
import CaregiverAPI
@testable import Caregiver

final class DynamicFormBuilderTests: XCTestCase {
    typealias Field = Components.Schemas.Field

    func testBuildsOneInputPerFieldInOrder() {
        let fields: [Field] = [
            .init(key: "systolic", label: "Systolic", _type: .number, unit: "mmHg", required: true),
            .init(key: "note", label: "Note", _type: .text),
        ]
        let inputs = DynamicFormBuilder.inputs(for: fields)
        XCTAssertEqual(inputs.map(\.key), ["systolic", "note"])
        XCTAssertEqual(inputs[0].kind, .number)
        XCTAssertEqual(inputs[0].unit, "mmHg")
        XCTAssertTrue(inputs[0].isRequired)
        XCTAssertFalse(inputs[1].isRequired) // nil required -> false
    }

    func testEnumFieldCarriesOptionsAndDefaultsToFirst() {
        let fields: [Field] = [
            .init(key: "mood", label: "Mood", _type: ._enum, options: ["good", "ok", "bad"]),
        ]
        let inputs = DynamicFormBuilder.inputs(for: fields)
        XCTAssertEqual(inputs[0].kind, .enumeration)
        XCTAssertEqual(inputs[0].options, ["good", "ok", "bad"])
        XCTAssertEqual(inputs[0].textValue, "good") // first option preselected
    }

    func testBooleanAndDatetimeKinds() {
        let fields: [Field] = [
            .init(key: "taken", label: "Taken", _type: .boolean),
            .init(key: "at", label: "At", _type: .datetime),
        ]
        let inputs = DynamicFormBuilder.inputs(for: fields)
        XCTAssertEqual(inputs[0].kind, .boolean)
        XCTAssertEqual(inputs[1].kind, .datetime)
    }
}
