import Foundation

/// Editable state for one field of a tracker's dynamic form. SwiftUI controls
/// bind to `textValue` / `boolValue` / `dateValue` depending on `kind`.
struct FieldInput: Identifiable, Equatable {
    enum Kind: Equatable { case number, text, boolean, enumeration, datetime }

    let key: String
    let label: String
    let kind: Kind
    let unit: String?
    let isRequired: Bool
    let options: [String]

    var textValue: String = ""     // number (as entered), text, enum (selected option)
    var boolValue: Bool = false    // boolean
    var dateValue: Date = .init()  // datetime

    var id: String { key }
}
