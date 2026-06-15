import Foundation
import CaregiverAPI

enum DynamicFormBuilder {
    typealias Field = Components.Schemas.Field

    /// Maps a tracker's fields to ordered, editable inputs.
    static func inputs(for fields: [Field]) -> [FieldInput] {
        fields.map { field in
            let options = field.options ?? []
            var input = FieldInput(
                key: field.key,
                label: field.label,
                kind: kind(for: field._type),
                unit: field.unit,
                isRequired: field.required ?? false,
                options: options
            )
            if input.kind == .enumeration, let first = options.first {
                input.textValue = first // preselect first option
            }
            return input
        }
    }

    private static func kind(for type: Components.Schemas.FieldType) -> FieldInput.Kind {
        switch type {
        case .number: return .number
        case .text: return .text
        case .boolean: return .boolean
        case ._enum: return .enumeration
        case .datetime: return .datetime
        }
    }
}
