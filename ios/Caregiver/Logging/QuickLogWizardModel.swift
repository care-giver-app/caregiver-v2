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
    var fieldErrors: [String: String] = [:]

    var allSucceeded: Bool { !results.isEmpty && results.allSatisfy(\.success) }
    var anySucceeded: Bool { results.contains(where: \.success) }

    // MARK: pure derivations (unit-tested)

    /// Selected trackers that have value fields, in roster order.
    static func needingDetails(_ trackers: [Components.Schemas.Tracker],
                               selected: Set<String>) -> [Components.Schemas.Tracker] {
        trackers.filter { selected.contains($0.trackerId) && !$0.fields.isEmpty }
    }

    /// Rebuild the detail queue after a selection change, reusing any prior entry
    /// (by tracker id) so already-entered values (including enum defaults the user
    /// changed) survive going back to select and forward again.
    static func rebuiltDetails(
        queue: [Components.Schemas.Tracker], prior: [QuickLogDetail]
    ) -> [QuickLogDetail] {
        let priorByID = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, $0) })
        return queue.map { tracker in
            priorByID[tracker.trackerId]
                ?? QuickLogDetail(tracker: tracker, inputs: DynamicFormBuilder.inputs(for: tracker.fields))
        }
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

    // MARK: load (spec decision 6 — standard state views drive off phase)

    func load(receiverID: String, using session: Session) async {
        phase = .loading
        do {
            trackers = try await session.api
                .listTrackers(path: .init(receiverId: receiverID))
                .ok.body.json.filter { !$0.archived }
            phase = .select
        } catch {
            phase = .loadError(AppError.from(error).message)
        }
    }

    // MARK: step flow

    func advance(using session: Session) async {
        switch phase {
        case .select:
            let queue = Self.needingDetails(trackers, selected: selected)
            details = Self.rebuiltDetails(queue: queue, prior: details)
            if details.isEmpty { await submit(using: session) }
            else { phase = .detail(0) }
        case .detail(let i):
            fieldErrors = DynamicFormBuilder.validate(details[i].inputs)
            guard fieldErrors.isEmpty else { return }
            if i + 1 < details.count { phase = .detail(i + 1) }
            else { await submit(using: session) }
        default:
            break
        }
    }

    func back() {
        if case .detail(let i) = phase {
            fieldErrors = [:]
            phase = i == 0 ? .select : .detail(i - 1)
        }
    }

    // MARK: submission (spec decision 5)

    /// One EventWrite per selected tracker; detail trackers carry their inputs/note,
    /// no-field trackers post empty values. Shared occurredAt.
    static func buildWrites(
        trackers: [Components.Schemas.Tracker], selected: Set<String>,
        details: [QuickLogDetail], occurredAt: Date
    ) throws -> [(trackerId: String, name: String, body: Components.Schemas.EventWrite)] {
        let detailByID = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        return try trackers.filter { selected.contains($0.trackerId) }.map { tracker in
            let detail = detailByID[tracker.trackerId]
            let note = detail?.note.isEmpty == false ? detail?.note : nil
            let body = Components.Schemas.EventWrite(
                occurredAt: occurredAt,
                values: try DynamicFormBuilder.valuesPayload(from: detail?.inputs ?? []),
                note: note)
            return (tracker.trackerId, tracker.name, body)
        }
    }

    func submit(using session: Session) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let writes: [(trackerId: String, name: String, body: Components.Schemas.EventWrite)]
        do {
            writes = try Self.buildWrites(trackers: trackers, selected: selected,
                                          details: details, occurredAt: occurredAt)
        } catch {
            phase = .results
            results = [QuickLogResult(trackerId: "-", name: "Preparing events",
                                      success: false, message: AppError.from(error).message)]
            return
        }
        let pending = Set(Self.pendingIDs(selected: writes.map(\.trackerId), results: results))
        let toPost = writes.filter { pending.contains($0.trackerId) }
        let api = session.api
        var newResults: [QuickLogResult] = []
        await withTaskGroup(of: QuickLogResult.self) { group in
            for write in toPost {
                group.addTask {
                    do {
                        switch try await api.logEvent(path: .init(trackerId: write.trackerId),
                                                      body: .json(write.body)) {
                        case .created:
                            return QuickLogResult(trackerId: write.trackerId, name: write.name,
                                                  success: true, message: nil)
                        case .badRequest(let b):
                            return QuickLogResult(trackerId: write.trackerId, name: write.name,
                                                  success: false,
                                                  message: (try? b.body.json.message) ?? "That didn't look right.")
                        default:
                            return QuickLogResult(trackerId: write.trackerId, name: write.name,
                                                  success: false, message: AppError.unknown.message)
                        }
                    } catch {
                        return QuickLogResult(trackerId: write.trackerId, name: write.name,
                                              success: false, message: AppError.from(error).message)
                    }
                }
            }
            for await result in group { newResults.append(result) }
        }
        // Merge: keep prior successes, replace/add everything just posted, in write order.
        let merged = writes.compactMap { write -> QuickLogResult? in
            newResults.first { $0.trackerId == write.trackerId }
                ?? results.first { $0.trackerId == write.trackerId }
        }
        results = merged
        if merged.contains(where: { !$0.success }) { phase = .results }
    }

    func retryFailed(using session: Session) async {
        await submit(using: session)   // pendingIDs already excludes successes
    }
}
