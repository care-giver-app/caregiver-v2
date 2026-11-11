import SwiftUI

/// What the tab shell has up over the `/v1` app for Quick log, and what it tells the
/// screens beneath once a run is done (PRD "Quick log" exits). Pure, so its routing is
/// tested without a view.
///
/// - Every way in opens Quick log for a receiver: the screen's own (Entry detail,
///   Tracker detail) or the active one (⊕, Home's empty day). With no receiver at all
///   there is nothing to record against, and the sheet says so.
/// - Done and Cancel are the sheet going back to whatever raised it. A run that saved
///   anything is counted in `runs`, which Home, Entry detail and Tracker detail watch to
///   read themselves again — so the screen it returns to already shows what was saved.
/// - Add a tracker swaps Quick log for Add tracker on the same receiver; a tracker made
///   there is pushed on Home's stack once the sheet is down.
struct QuickLogPresenter: Equatable {
    enum Sheet: Equatable, Identifiable {
        case quickLog(QuickLogStart, TeamReceiver)
        case addTracker(TeamReceiver)
        /// ⊕ with nobody to look after yet.
        case noReceiver

        var id: String {
            switch self {
            case .quickLog(let start, let r): "quickLog-\(r.id)-\(start.id)"
            case .addTracker(let r): "addTracker-\(r.id)"
            case .noReceiver: "noReceiver"
            }
        }
    }

    /// A tracker Add tracker made in Quick log's place, pushed once its sheet is down.
    struct Created: Equatable {
        let trackerID: String
        let receiver: TeamReceiver
    }

    var sheet: Sheet?
    private(set) var runs = QuickLogRuns()
    private(set) var created: Created?

    mutating func open(_ start: QuickLogStart, receiver: TeamReceiver?) {
        sheet = receiver.map { .quickLog(start, $0) } ?? .noReceiver
    }

    /// Quick log's Add a tracker: it goes, and Add tracker takes its place.
    mutating func swapToAddTracker(_ receiver: TeamReceiver) {
        guard case .quickLog = sheet else { return }
        sheet = .addTracker(receiver)
    }

    /// Quick log has gone, by Done, Cancel or a swipe. A run that saved anything is
    /// counted, with how it went, for the screens beneath to read themselves again.
    mutating func quickLogEnded(_ outcome: QuickLogModel.Outcome?) {
        guard let outcome, outcome.savedAny else { return }
        runs = QuickLogRuns(count: runs.count + 1, last: outcome)
    }

    mutating func trackerCreated(_ id: String, receiver: TeamReceiver) {
        created = Created(trackerID: id, receiver: receiver)
    }

    /// The tracker to push now that the sheet is down, once.
    mutating func takeCreated() -> Created? {
        defer { created = nil }
        return created
    }
}

/// How many Quick log runs have saved something, and how the last went. Watched by the
/// screens a run returns to.
struct QuickLogRuns: Equatable, Sendable {
    var count = 0
    var last: QuickLogModel.Outcome?
}

private struct QuickLogRunsKey: EnvironmentKey {
    static let defaultValue = QuickLogRuns()
}

extension EnvironmentValues {
    var v1QuickLogRuns: QuickLogRuns {
        get { self[QuickLogRunsKey.self] }
        set { self[QuickLogRunsKey.self] = newValue }
    }
}
