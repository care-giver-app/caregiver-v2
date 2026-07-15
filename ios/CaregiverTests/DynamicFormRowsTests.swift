import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

final class DynamicFormRowsTests: XCTestCase {
    private func field(_ key: String, _ label: String, _ type: Components.Schemas.FieldType, unit: String? = nil) -> Components.Schemas.Field {
        .init(key: key, label: label, _type: type, unit: unit)
    }

    func testBuildsRowsInFieldOrderSkippingMissing() throws {
        let fields = [
            field("sys", "Systolic", .number, unit: "mmHg"),
            field("taken", "Taken", .boolean),
            field("note", "Extra", .text),  // no value → skipped
        ]
        let values = Components.Schemas.Event.ValuesPayload(
            additionalProperties: try OpenAPIObjectContainer(unvalidatedValue: [
                "sys": 128.0, "taken": true,
            ]))

        let rows = DynamicFormBuilder.rows(values: values, fields: fields)

        XCTAssertEqual(rows, [
            .init(label: "Systolic", value: "128", unit: "mmHg"),
            .init(label: "Taken", value: "Yes", unit: nil),
        ])
    }
}
