import Foundation

/// A stretch of days to narrow Tracker detail's entries to — `yyyy-MM-dd` in the
/// receiver's zone, both ends inclusive.
struct EntryDateRange: Equatable, Sendable {
    let from: String
    let to: String
}

/// Tracker detail's entries, newest first: the most recent page, and more as a
/// caregiver scrolls (PRD "Tracker detail"). Changing the range starts over.
@MainActor
@Observable
final class EntriesPager {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading
    private(set) var entries: [TrackerEntry] = []
    private(set) var isLoadingMore = false
    /// A page after the first failed; the list stays and offers to try again.
    private(set) var moreFailed = false
    private(set) var range: EntryDateRange?
    /// A refresh of a loaded list failed; the list stays as it was.
    private(set) var refreshFailed = false

    private var isRefreshing = false

    private var nextCursor: String?
    private var seen = Set<String>()
    /// Bumped on every restart, so an answer to an earlier range is dropped.
    private var generation = 0

    private let trackerID: String
    private let fetch: @Sendable (_ trackerID: String, _ query: EntriesQuery) async throws -> EntriesPage

    init(trackerID: String,
         fetch: @escaping @Sendable (_ trackerID: String, _ query: EntriesQuery) async throws -> EntriesPage) {
        self.trackerID = trackerID
        self.fetch = fetch
    }

    /// True once the last page has arrived.
    var isExhausted: Bool { phase == .loaded && nextCursor == nil }

    /// The first page, for the current range.
    func reload() async {
        generation += 1
        let mine = generation
        phase = .loading
        entries = []
        seen = []
        nextCursor = nil
        moreFailed = false
        refreshFailed = false
        isLoadingMore = false
        isRefreshing = false
        do {
            let page = try await fetch(trackerID, EntriesQuery(from: range?.from, to: range?.to, cursor: nil))
            guard mine == generation else { return }
            append(page)
            phase = .loaded
        } catch {
            guard mine == generation else { return }
            phase = .failed(AppError.from(error))
        }
    }

    /// Pull to refresh: once a list is showing, it stays until a fresh first page
    /// arrives and replaces it; a failure leaves it and sets `refreshFailed`. Before
    /// then, the same as `reload()`.
    func refresh() async {
        guard phase == .loaded else { return await reload() }
        generation += 1
        let mine = generation
        isRefreshing = true
        isLoadingMore = false
        defer { if mine == generation { isRefreshing = false } }
        do {
            let page = try await fetch(trackerID, EntriesQuery(from: range?.from, to: range?.to, cursor: nil))
            guard mine == generation else { return }
            entries = []
            seen = []
            moreFailed = false
            refreshFailed = false
            append(page)
        } catch {
            guard mine == generation else { return }
            refreshFailed = true
        }
    }

    /// Narrows to `range` (nil for all of them) and starts over from its newest entry.
    func setRange(_ range: EntryDateRange?) async {
        guard range != self.range else { return }
        self.range = range
        await reload()
    }

    /// The next page, if there is one and none is already on its way.
    func loadMore() async {
        guard phase == .loaded, let cursor = nextCursor, !isLoadingMore, !isRefreshing else { return }
        let mine = generation
        isLoadingMore = true
        moreFailed = false
        defer { if mine == generation { isLoadingMore = false } }
        do {
            let page = try await fetch(trackerID, EntriesQuery(from: range?.from, to: range?.to, cursor: cursor))
            guard mine == generation else { return }
            append(page)
        } catch {
            guard mine == generation else { return }
            moreFailed = true
        }
    }

    /// Called as `entry` comes on screen: the last one asks for the next page.
    func entryAppeared(_ entry: TrackerEntry) async {
        if entry.id == entries.last?.id { await loadMore() }
    }

    private func append(_ page: EntriesPage) {
        for entry in page.entries where seen.insert(entry.id).inserted {
            entries.append(entry)
        }
        nextCursor = page.nextCursor
    }
}
