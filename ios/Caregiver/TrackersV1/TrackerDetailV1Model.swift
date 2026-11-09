import Foundation

/// Tracker detail: what one tracker is and how it is doing, and its entries.
@MainActor
@Observable
final class TrackerDetailV1Model {
    enum Phase: Equatable {
        case loading
        case loaded(TrackerProfile)
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading
    /// A refresh of the loaded tracker failed; what was showing stays.
    private(set) var refreshFailed = false
    let entries: EntriesPager
    let trackerID: String
    let receiver: TeamReceiver

    private let service: TrackersService

    init(trackerID: String, receiver: TeamReceiver, service: TrackersService) {
        self.trackerID = trackerID
        self.receiver = receiver
        self.service = service
        self.entries = EntriesPager(trackerID: trackerID, fetch: service.listEntries)
    }

    var profile: TrackerProfile? {
        if case .loaded(let p) = phase { return p }
        return nil
    }

    /// The tracker and its first page of entries, side by side. Once loaded, this is
    /// a refresh: what is showing stays until the answers replace it, and a failure
    /// keeps it and says so (`refreshFailed`, `entries.refreshFailed`).
    func load() async {
        async let detail: Void = loadDetail()
        async let firstPage: Void = entries.refresh()
        _ = await (detail, firstPage)
    }

    /// Either refresh failed, so the screen shows what it had and says so.
    var showsRefreshFailure: Bool { refreshFailed || entries.refreshFailed }

    func retry() async {
        phase = .loading
        await load()
    }

    private func loadDetail() async {
        do {
            phase = .loaded(try await service.trackerDetail(trackerID))
            refreshFailed = false
        } catch {
            if profile == nil {
                phase = .failed(AppError.from(error))
            } else {
                refreshFailed = true
            }
        }
    }
}

/// Schedules: one tracker's schedules, read by anyone on the team.
@MainActor
@Observable
final class SchedulesV1Model {
    enum Phase: Equatable {
        case loading
        case loaded([TrackerScheduleItem])
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading
    /// A refresh of the loaded schedules failed; what was showing stays.
    private(set) var refreshFailed = false
    private let trackerID: String
    private let service: TrackersService

    init(trackerID: String, service: TrackersService) {
        self.trackerID = trackerID
        self.service = service
    }

    /// The first load, or — once loaded — a refresh that keeps what is showing on failure.
    func load() async {
        do {
            phase = .loaded(try await service.listSchedules(trackerID))
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

/// TEMPORARY, until Home is built: resolves the care receiver behind V1PlaceholderView's
/// "All trackers" — the account's first care team, and that team's first receiver
/// (the API lists them oldest first).
@MainActor
@Observable
final class AllTrackersEntryModel {
    enum Outcome: Equatable {
        case idle
        case noReceivers(teamName: String)
        case failed(AppError)
    }

    private(set) var isLoading = false
    private(set) var outcome: Outcome = .idle
    /// Set when there is a receiver to push the Trackers list for.
    var receiver: TeamReceiver?

    private let team: Account.Team
    private let service: TrackersService

    init(team: Account.Team, service: TrackersService) {
        self.team = team
        self.service = service
    }

    func open() async {
        guard !isLoading else { return }
        isLoading = true
        outcome = .idle
        defer { isLoading = false }
        do {
            if let first = try await service.listReceivers(team.teamID).first {
                receiver = first.managed(by: team)
            } else {
                outcome = .noReceivers(teamName: team.name)
            }
        } catch {
            outcome = .failed(AppError.from(error))
        }
    }
}
