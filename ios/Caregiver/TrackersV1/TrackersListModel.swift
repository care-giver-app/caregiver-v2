import Foundation

/// The three views of the Trackers list (PRD "Trackers"). All three are drawn from
/// one response, so their counts agree with what each shows.
enum TrackerListFilter: CaseIterable, Equatable, Sendable {
    case active, needsAttention, paused

    var title: String {
        switch self {
        case .active: "Active"
        case .needsAttention: "Needs attention"
        case .paused: "Paused"
        }
    }

    func includes(_ tracker: TrackerItem) -> Bool {
        switch self {
        case .active: tracker.status == .active
        // A paused tracker's thresholds have stopped, so it is never in trouble.
        case .needsAttention: tracker.status == .active && tracker.needsAttention
        case .paused: tracker.status == .paused
        }
    }

    /// What the chosen view says when it holds nothing, though the receiver has trackers.
    var emptyLine: String {
        switch self {
        case .active: "No active trackers."
        case .needsAttention: "Nothing needs attention."
        case .paused: "No paused trackers."
        }
    }
}

/// The Trackers list: every tracker of one care receiver, in three filtered views.
@MainActor
@Observable
final class TrackersListModel {
    enum Phase: Equatable {
        case loading
        case loaded([TrackerItem])
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading
    /// A refresh of the loaded list failed; what was showing stays.
    private(set) var refreshFailed = false
    /// The instant row recency is said against, taken afresh on every load.
    private(set) var now: Date
    /// Opens on active every time: a new model per visit, never remembered (PRD).
    var filter: TrackerListFilter = .active

    let receiver: TeamReceiver
    private let service: TrackersService
    private let clock: @MainActor () -> Date

    init(receiver: TeamReceiver, service: TrackersService, clock: @escaping @MainActor () -> Date = Date.init) {
        self.receiver = receiver
        self.service = service
        self.clock = clock
        self.now = clock()
    }

    private var trackers: [TrackerItem] {
        if case .loaded(let all) = phase { return all }
        return []
    }

    /// The receiver has no trackers at all — not the same as an empty filter.
    var hasNoTrackers: Bool {
        if case .loaded(let all) = phase { return all.isEmpty }
        return false
    }

    func count(_ filter: TrackerListFilter) -> Int {
        trackers.filter(filter.includes).count
    }

    /// "Active · 6".
    func chipLabel(_ filter: TrackerListFilter) -> String {
        "\(filter.title) · \(count(filter))"
    }

    /// The chosen view, in the server's alphabetical order — it never rearranges.
    var visible: [TrackerItem] {
        trackers.filter(filter.includes)
    }

    /// The first load, or — once loaded — a refresh that keeps what is showing on
    /// failure. The view calls it again each time the list reappears (back from a
    /// tracker, say), so what changed there, and how long ago things were, shows here.
    func load() async {
        now = clock()
        do {
            phase = .loaded(try await service.listTrackers(receiver.id))
            refreshFailed = false
        } catch {
            if case .loaded = phase {
                refreshFailed = true
            } else {
                phase = .failed(AppError.from(error))
            }
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }
}
