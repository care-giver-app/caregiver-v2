import Foundation
import CaregiverAPI

/// The Aurora tracker-hue palette offered by the add-tracker color picker
/// (add-tracker.md decision 9/12) — cyan/teal/violet/info-blue only; status colors
/// (amber/red) are excluded so they don't collide with recency/breach semantics.
/// Pure (hex only, no `Color`) so it stays nonisolated and unit-testable; the
/// SwiftUI `Color` mapping lives view-side.
enum TrackerHue: String, CaseIterable, Equatable {
    case cyan, teal, violet, infoBlue

    var hex: String {
        switch self {
        case .cyan: "4dd6e6"
        case .teal: "3db8c4"
        case .violet: "7c6ff0"
        case .infoBlue: "93C5FD"
        }
    }
}

/// Editable min/max text for one field's alert threshold (add-tracker.md decision 13).
/// A bound that doesn't parse to a number counts as "no limit".
struct ThresholdText: Equatable {
    var min: String
    var max: String

    init(min: String = "", max: String = "") {
        self.min = min
        self.max = max
    }

    var parsedMin: Double? { Double(min.trimmingCharacters(in: .whitespaces)) }
    var parsedMax: Double? { Double(max.trimmingCharacters(in: .whitespaces)) }
    var isEmpty: Bool { parsedMin == nil && parsedMax == nil }
}

/// Pure helpers for the add-tracker wizard (mirrors `QuickLogWizardModel`'s
/// pure-statics style; kept off the `@MainActor` model so tests call freely).
enum AddTrackerLogic {
    /// Canonical template → Aurora hue map (add-tracker.md decision 12 / sample-data.md).
    static func hue(forTemplateID id: String) -> TrackerHue {
        switch id {
        case "blood_pressure": .cyan
        case "weight": .teal
        case "medication": .violet
        case "temperature": .infoBlue
        case "meal": .teal
        case "mood": .violet
        default: .cyan
        }
    }

    /// The raw contract `kind` shown as the card badge (decision 10).
    static func kindLabel(_ kind: Components.Schemas.TrackerKind) -> String {
        switch kind {
        case .event: "Event"
        case .measurement: "Measurement"
        case .scheduled: "Scheduled"
        }
    }

    /// Builds the `TrackerWrite` from the chosen template plus the user's edits:
    /// trimmed name, picked Aurora `colorHex`, and per-field threshold overrides.
    /// A field key present in `thresholds` is rebound to the edited min/max (both
    /// blank ⇒ threshold dropped); a key absent from the dict keeps the template's
    /// threshold untouched.
    static func makeWrite(
        template: Components.Schemas.TrackerTemplate,
        name: String,
        colorHex: String,
        thresholds: [String: ThresholdText]
    ) -> Components.Schemas.TrackerWrite {
        let fields = template.fields.map { field -> Components.Schemas.Field in
            var updated = field
            if let edit = thresholds[field.key] {
                updated.threshold = edit.isEmpty
                    ? nil
                    : Components.Schemas.Threshold(min: edit.parsedMin, max: edit.parsedMax)
            }
            return updated
        }
        return Components.Schemas.TrackerWrite(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: template.kind,
            icon: template.icon,
            color: colorHex,
            fields: fields
        )
    }
}
