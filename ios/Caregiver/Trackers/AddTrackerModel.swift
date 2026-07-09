import Foundation
import CaregiverAPI

/// Drives the add-tracker wizard (ios/specs/views/add-tracker.md): load the seeded
/// template catalog, hold the chosen template's editable config (name, Aurora hue,
/// per-number-field thresholds), and submit a `createTracker`. Pure step logic lives
/// in `AddTrackerLogic`; this is the API-touching + state layer.
@MainActor
@Observable
final class AddTrackerModel {
    enum Phase: Equatable {
        case loading
        case choose
        case configure
        case loadError(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var templates: [Components.Schemas.TrackerTemplate] = []

    // Editable config for the chosen template.
    private(set) var selected: Components.Schemas.TrackerTemplate?
    var name = ""
    var selectedHue: TrackerHue = .cyan
    /// Keyed by `Field.key`; seeded for every `number` field on `choose`.
    var thresholds: [String: ThresholdText] = [:]

    var isSubmitting = false
    var submitError: String?

    func load(using session: Session) async {
        phase = .loading
        do {
            templates = try await session.api.listTrackerTemplates().ok.body.json
            phase = .choose
        } catch {
            phase = .loadError(AppError.from(error).message)
        }
    }

    /// Enter the Configure step, pre-filling name/hue/threshold text from the template.
    func choose(_ template: Components.Schemas.TrackerTemplate) {
        selected = template
        name = template.name
        selectedHue = AddTrackerLogic.hue(forTemplateID: template.templateId)
        var seeded: [String: ThresholdText] = [:]
        for field in template.fields where field._type == .number {
            seeded[field.key] = ThresholdText(
                min: field.threshold?.min.map(Self.format) ?? "",
                max: field.threshold?.max.map(Self.format) ?? ""
            )
        }
        thresholds = seeded
        submitError = nil
        phase = .configure
    }

    func backToChoose() {
        selected = nil
        submitError = nil
        phase = .choose
    }

    func submit(receiverId: String, using session: Session, onCreated: () -> Void) async {
        guard let template = selected else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { submitError = "Enter a name."; return }
        isSubmitting = true
        submitError = nil
        let body = AddTrackerLogic.makeWrite(
            template: template, name: trimmed,
            colorHex: selectedHue.hex, thresholds: thresholds
        )
        do {
            _ = try await session.api.createTracker(
                path: .init(receiverId: receiverId), body: .json(body)
            )
            onCreated()
        } catch {
            submitError = AppError.from(error).message
        }
        isSubmitting = false
    }

    /// Whole numbers render without a trailing ".0"; fractions keep their digits.
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
