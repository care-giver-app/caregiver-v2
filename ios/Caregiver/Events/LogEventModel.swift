import Foundation
import CaregiverAPI

@MainActor
@Observable
final class LogEventModel {
    var inputs: [FieldInput] = []
    var occurredAt: Date = .init()
    var note: String = ""
    var fieldErrors: [String: String] = [:]
    var formError: AppError?
    var isBusy = false

    private let tracker: Components.Schemas.Tracker
    private let existing: Components.Schemas.Event?

    init(tracker: Components.Schemas.Tracker, existing: Components.Schemas.Event?) {
        self.tracker = tracker
        self.existing = existing
        self.inputs = DynamicFormBuilder.inputs(for: tracker.fields)
        if let existing {
            self.occurredAt = existing.occurredAt
            self.note = existing.note ?? ""
            DynamicFormBuilder.prefill(&self.inputs, from: existing.values)
        }
    }

    /// Submits; returns true on success (caller dismisses + refreshes).
    func submit(using session: Session) async -> Bool {
        fieldErrors = DynamicFormBuilder.validate(inputs)
        guard fieldErrors.isEmpty else { return false }
        isBusy = true; formError = nil; defer { isBusy = false }
        do {
            let body = Components.Schemas.EventWrite(
                occurredAt: occurredAt,
                values: try DynamicFormBuilder.valuesPayload(from: inputs),
                note: note.isEmpty ? nil : note
            )
            if let existing {
                switch try await session.api.updateEvent(
                    path: .init(trackerId: tracker.trackerId, eventId: existing.eventId), body: .json(body)
                ) {
                case .ok: return true
                case .badRequest(let b): formError = AppError(message: (try? b.body.json.message) ?? "That didn't look right."); return false
                default: formError = .unknown; return false
                }
            } else {
                switch try await session.api.logEvent(path: .init(trackerId: tracker.trackerId), body: .json(body)) {
                case .created: return true
                case .badRequest(let b): formError = AppError(message: (try? b.body.json.message) ?? "That didn't look right."); return false
                default: formError = .unknown; return false
                }
            }
        } catch {
            formError = AppError.from(error); return false
        }
    }
}
