import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class DynamicFormValuesTests: XCTestCase {
    func testPayloadCoercesScalarsByKind() throws {
        var n = FieldInput(key: "systolic", label: "Systolic", kind: .number, unit: "mmHg", isRequired: true, options: [])
        n.textValue = "120"
        var b = FieldInput(key: "taken", label: "Taken", kind: .boolean, unit: nil, isRequired: false, options: [])
        b.boolValue = true
        var e = FieldInput(key: "mood", label: "Mood", kind: .enumeration, unit: nil, isRequired: false, options: ["good"])
        e.textValue = "good"

        let payload = try DynamicFormBuilder.valuesPayload(from: [n, b, e])
        let dict = payload.additionalProperties.value
        XCTAssertEqual(dict["systolic"] as? Double, 120)
        XCTAssertEqual(dict["taken"] as? Bool, true)
        XCTAssertEqual(dict["mood"] as? String, "good")
    }

    func testScheduledValuesPayloadCoercesScalarsByKind() throws {
        var n = FieldInput(key: "doctor", label: "Doctor", kind: .text, unit: nil, isRequired: true, options: [])
        n.textValue = "Dr. Lee"
        let payload = try DynamicFormBuilder.scheduledValuesPayload(from: [n])
        XCTAssertEqual(payload.additionalProperties.value["doctor"] as? String, "Dr. Lee")
    }

    func testOptionalEmptyNumberIsOmitted() throws {
        var n = FieldInput(key: "weight", label: "Weight", kind: .number, unit: nil, isRequired: false, options: [])
        n.textValue = ""
        let payload = try DynamicFormBuilder.valuesPayload(from: [n])
        XCTAssertNil(payload.additionalProperties.value["weight"] ?? nil)
    }

    func testDisplayRendersKeyedSummary() {
        let values = try! OpenAPIObjectContainer(unvalidatedValue: ["systolic": 120.0, "taken": true])
        let event = makeEvent(values: values)
        let fields: [Components.Schemas.Field] = [
            .init(key: "systolic", label: "Systolic", _type: .number, unit: "mmHg"),
            .init(key: "taken", label: "Taken", _type: .boolean),
        ]
        let summary = DynamicFormBuilder.display(values: event.values, fields: fields)
        XCTAssertTrue(summary.contains("Systolic: 120"))
        XCTAssertTrue(summary.contains("mmHg"))
        XCTAssertTrue(summary.contains("Taken: Yes"))
    }

    // Helper: build an Event with given values (other required fields are filler).
    private func makeEvent(values: OpenAPIObjectContainer) -> Components.Schemas.Event {
        .init(
            trackerId: "t",
            eventId: "e",
            careGroupId: "g",
            receiverId: "r",
            values: .init(additionalProperties: values),
            occurredAt: Date(timeIntervalSince1970: 0),
            loggedBy: "u",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
