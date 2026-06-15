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

    /// Client-side mirror of the server's ValidateValues. Returns field-key -> message
    /// for invalid inputs (empty dictionary = valid).
    static func validate(_ inputs: [FieldInput]) -> [String: String] {
        var errors: [String: String] = [:]
        for input in inputs {
            let trimmed = input.textValue.trimmingCharacters(in: .whitespaces)
            switch input.kind {
            case .number:
                if trimmed.isEmpty {
                    if input.isRequired { errors[input.key] = "\(input.label) is required." }
                } else if Double(trimmed) == nil {
                    errors[input.key] = "\(input.label) must be a number."
                }
            case .text:
                if input.isRequired && trimmed.isEmpty {
                    errors[input.key] = "\(input.label) is required."
                }
            case .enumeration:
                if trimmed.isEmpty {
                    if input.isRequired { errors[input.key] = "\(input.label) is required." }
                } else if !input.options.contains(trimmed) {
                    errors[input.key] = "\(input.label) must be one of: \(input.options.joined(separator: ", "))."
                }
            case .boolean, .datetime:
                break // always have a value
            }
        }
        return errors
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
