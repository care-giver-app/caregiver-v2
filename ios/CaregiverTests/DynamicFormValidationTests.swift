import XCTest
@testable import Caregiver

final class DynamicFormValidationTests: XCTestCase {
    private func numberInput(_ key: String, required: Bool, value: String) -> FieldInput {
        var i = FieldInput(key: key, label: key, kind: .number, unit: nil, isRequired: required, options: [])
        i.textValue = value
        return i
    }

    func testRequiredEmptyNumberFails() {
        let errors = DynamicFormBuilder.validate([numberInput("systolic", required: true, value: "")])
        XCTAssertNotNil(errors["systolic"])
    }

    func testNonNumericNumberFails() {
        let errors = DynamicFormBuilder.validate([numberInput("systolic", required: true, value: "abc")])
        XCTAssertNotNil(errors["systolic"])
    }

    func testValidNumberPasses() {
        let errors = DynamicFormBuilder.validate([numberInput("systolic", required: true, value: "120")])
        XCTAssertTrue(errors.isEmpty)
    }

    func testOptionalEmptyNumberPasses() {
        let errors = DynamicFormBuilder.validate([numberInput("weight", required: false, value: "")])
        XCTAssertTrue(errors.isEmpty)
    }

    func testEnumNotInOptionsFails() {
        var i = FieldInput(key: "mood", label: "Mood", kind: .enumeration, unit: nil, isRequired: true, options: ["good", "bad"])
        i.textValue = "meh"
        XCTAssertNotNil(DynamicFormBuilder.validate([i])["mood"])
    }

    func testRequiredTextEmptyFails() {
        let i = FieldInput(key: "note", label: "Note", kind: .text, unit: nil, isRequired: true, options: [])
        XCTAssertNotNil(DynamicFormBuilder.validate([i])["note"])
    }

    func testBooleanAndDatetimeAlwaysValid() {
        let b = FieldInput(key: "taken", label: "Taken", kind: .boolean, unit: nil, isRequired: true, options: [])
        let d = FieldInput(key: "at", label: "At", kind: .datetime, unit: nil, isRequired: true, options: [])
        XCTAssertTrue(DynamicFormBuilder.validate([b, d]).isEmpty)
    }
}
