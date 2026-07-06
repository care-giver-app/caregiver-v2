import Foundation
import OpenAPIRuntime
import CaregiverAPI

extension Components.Schemas.Tracker: @retroactive Identifiable {
    public var id: String { trackerId }
}

/// One selected tracker that has value fields, i.e. gets its own detail step.
struct QuickLogDetail: Identifiable {
    let tracker: Components.Schemas.Tracker
    var inputs: [FieldInput]
    var note: String = ""
    var id: String { tracker.trackerId }
}

/// Outcome of one logEvent POST in the fan-out (spec decision 5).
struct QuickLogResult: Identifiable, Equatable {
    let trackerId: String
    let name: String
    var success: Bool
    var message: String?
    var id: String { trackerId }
}

/// Drives the quick-log wizard (ios/specs/views/logging.md): select → detail(i) → results.
@MainActor @Observable
final class QuickLogWizardModel {
    enum Phase: Equatable {
        case loading
        case loadError(String)
        case select
        case detail(Int)
        case results
    }

    var phase: Phase = .loading
    var trackers: [Components.Schemas.Tracker] = []
    var selected: Set<String> = []
    var occurredAt = Date()
    var details: [QuickLogDetail] = []
    var results: [QuickLogResult] = []
    var isBusy = false

    // MARK: pure derivations (unit-tested)

    /// Selected trackers that have value fields, in roster order.
    static func needingDetails(_ trackers: [Components.Schemas.Tracker],
                               selected: Set<String>) -> [Components.Schemas.Tracker] {
        trackers.filter { selected.contains($0.trackerId) && !$0.fields.isEmpty }
    }

    /// "2 of 4 trackers need details" — nil when nothing needs details.
    static func helperText(selectedCount: Int, needingDetails: Int) -> String? {
        guard selectedCount > 0, needingDetails > 0 else { return nil }
        return "\(needingDetails) of \(selectedCount) trackers need details"
    }

    /// "Next" while detail steps remain ahead, else "Log N events".
    static func primaryTitle(selectedCount: Int, remainingDetailSteps: Int) -> String {
        if remainingDetailSteps > 0 { return "Next" }
        return selectedCount == 1 ? "Log 1 event" : "Log \(selectedCount) events"
    }

    /// Tracker ids still owed a POST: everything selected minus prior successes (decision 5).
    static func pendingIDs(selected: [String], results: [QuickLogResult]) -> [String] {
        let succeeded = Set(results.filter(\.success).map(\.trackerId))
        return selected.filter { !succeeded.contains($0) }
    }
}
