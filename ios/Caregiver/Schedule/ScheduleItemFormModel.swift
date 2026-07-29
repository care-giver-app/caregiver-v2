import Foundation
import CaregiverAPI

/// Drives the "schedule a new item" form for a `scheduled`-kind tracker
/// (ios/specs/views/schedule.md). Mirrors `LogEventModel`, swapping `occurredAt`
/// for a `scheduledFor` date and `logEvent`/`updateEvent` for `createScheduledItem`.
@MainActor
@Observable
final class ScheduleItemFormModel {
    var inputs: [FieldInput] = []
    var scheduledFor: Date = .init()
    var note: String = ""
    var fieldErrors: [String: String] = [:]
    var formError: AppError?
    var isBusy = false

    private let tracker: Components.Schemas.Tracker

    init(tracker: Components.Schemas.Tracker) {
        self.tracker = tracker
        self.inputs = DynamicFormBuilder.inputs(for: tracker.fields)
    }

    /// Submits; returns true on success (caller dismisses + refreshes).
    func submit(using session: Session) async -> Bool {
        fieldErrors = DynamicFormBuilder.validate(inputs)
        guard fieldErrors.isEmpty else { return false }
        isBusy = true; formError = nil; defer { isBusy = false }
        do {
            let body = Components.Schemas.ScheduledItemWrite(
                scheduledFor: scheduledFor,
                values: try DynamicFormBuilder.scheduledValuesPayload(from: inputs),
                note: note.isEmpty ? nil : note
            )
            switch try await session.api.createScheduledItem(path: .init(trackerId: tracker.trackerId), body: .json(body)) {
            case .created: return true
            case .badRequest(let b): formError = AppError(message: (try? b.body.json.message) ?? "That didn't look right."); return false
            default: formError = .unknown; return false
            }
        } catch {
            formError = AppError.from(error); return false
        }
    }
}
