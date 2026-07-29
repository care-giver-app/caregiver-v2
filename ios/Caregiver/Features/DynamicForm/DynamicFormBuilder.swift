import Foundation
import OpenAPIRuntime
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
            if input.kind == .enumeration, input.isRequired, let first = options.first {
                input.textValue = first // preselect first option — required only, optional starts blank
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

    /// Coerces validated inputs into a raw values dict. Optional empty fields are
    /// omitted. datetime is encoded as an ISO8601 string (values is free-form
    /// JSON). Call only after `validate` returns no errors. Shared by both
    /// `EventWrite` and `ScheduledItemWrite`, which carry structurally identical
    /// but nominally distinct `values` payload types.
    static func rawValues(from inputs: [FieldInput]) -> [String: (any Sendable)?] {
        var dict: [String: (any Sendable)?] = [:]
        let iso = ISO8601DateFormatter()
        for input in inputs {
            let trimmed = input.textValue.trimmingCharacters(in: .whitespaces)
            switch input.kind {
            case .number:
                if let d = Double(trimmed) { dict[input.key] = d }
            case .text, .enumeration:
                if !trimmed.isEmpty { dict[input.key] = trimmed }
            case .boolean:
                dict[input.key] = input.boolValue
            case .datetime:
                dict[input.key] = iso.string(from: input.dateValue)
            }
        }
        return dict
    }

    /// Builds the EventWrite values payload from validated inputs.
    static func valuesPayload(from inputs: [FieldInput]) throws -> Components.Schemas.EventWrite.ValuesPayload {
        .init(additionalProperties: try OpenAPIObjectContainer(unvalidatedValue: rawValues(from: inputs)))
    }

    /// Builds the ScheduledItemWrite values payload from validated inputs.
    static func scheduledValuesPayload(from inputs: [FieldInput]) throws -> Components.Schemas.ScheduledItemWrite.ValuesPayload {
        .init(additionalProperties: try OpenAPIObjectContainer(unvalidatedValue: rawValues(from: inputs)))
    }

    /// Re-hydrates inputs from an existing event's values (for editing).
    static func prefill(_ inputs: inout [FieldInput], from values: Components.Schemas.Event.ValuesPayload) {
        let raw = values.additionalProperties.value
        let iso = ISO8601DateFormatter()
        for index in inputs.indices {
            guard let value = raw[inputs[index].key] ?? nil else { continue }
            switch inputs[index].kind {
            case .number:
                if let d = value as? Double { inputs[index].textValue = d == d.rounded() ? String(Int(d)) : String(d) }
                else if let i = value as? Int { inputs[index].textValue = String(i) }
            case .text, .enumeration:
                if let s = value as? String { inputs[index].textValue = s }
            case .boolean:
                if let b = value as? Bool { inputs[index].boolValue = b }
            case .datetime:
                if let s = value as? String, let date = iso.date(from: s) { inputs[index].dateValue = date }
            }
        }
    }

    struct ValueRow: Equatable {
        let label: String
        let value: String
        let unit: String?
    }

    /// One row per field that has a value, in field order. The event-detail
    /// screen renders these as label · value · unit (replaces the single `display` string).
    static func rows(values: Components.Schemas.Event.ValuesPayload, fields: [Field]) -> [ValueRow] {
        let raw = values.additionalProperties.value
        return fields.compactMap { field in
            guard let value = raw[field.key] ?? nil else { return nil }
            return ValueRow(label: field.label, value: render(value), unit: field.unit)
        }
    }

    /// One-line history summary, e.g. "Systolic: 120 mmHg · Taken: Yes".
    static func display(values: Components.Schemas.Event.ValuesPayload, fields: [Field]) -> String {
        let raw = values.additionalProperties.value
        let parts: [String] = fields.compactMap { field in
            guard let value = raw[field.key] ?? nil else { return nil }
            let rendered = render(value)
            let unit = field.unit.map { " \($0)" } ?? ""
            return "\(field.label): \(rendered)\(unit)"
        }
        return parts.joined(separator: " · ")
    }

    private static func render(_ value: any Sendable) -> String {
        switch value {
        case let b as Bool: return b ? "Yes" : "No"
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        case let i as Int: return String(i)
        case let s as String: return s
        default: return String(describing: value)
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
