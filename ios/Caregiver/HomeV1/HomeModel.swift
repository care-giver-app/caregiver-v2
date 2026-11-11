import Foundation

/// Home for one care receiver (PRD "Home"): what needs attention, what is coming up, and
/// one day of the timeline in the receiver's time zone. A new receiver — Team switched who
/// Home is about — starts over on today; the same receiver again is a refresh in place.
@MainActor
@Observable
final class HomeModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(AppError)
    }

    /// The day's timeline loads apart from the rest, since stepping days reloads only it.
    enum DayPhase: Equatable {
        case loading
        case loaded([DayItem])
        case failed
    }

    /// What Home shows above coming up, in the PRD's order of precedence: a receiver with
    /// no active trackers outranks the all-clear state, which a receiver with nothing
    /// tracked would otherwise always be in.
    enum Status: Equatable {
        case noActiveTrackers
        case needsAttention([AttentionItem])
        case allClear
    }

    /// What an empty day offers.
    enum DayOffer: Hashable {
        case logAnEntry
        case writeANote
    }

    /// Home shows at most three of each (PRD "Needs attention", "Coming up").
    static let sectionLimit = 3

    private(set) var receiver: TeamReceiver?
    private(set) var phase: Phase = .loading
    private(set) var attention: [AttentionItem] = []
    private(set) var comingUp: [ReceiverEntryItem] = []
    /// Every tracker of the receiver, paused ones included — only to know whether any is active.
    private(set) var trackers: [TrackerItem] = []
    /// The day the timeline shows, in the receiver's zone.
    private(set) var day: LocalDay
    private(set) var dayPhase: DayPhase = .loading
    /// Each timeline tracker's fields, so an entry's values can be labeled. Best effort:
    /// a tracker whose fields could not be read shows its entries without values. Kept
    /// while stepping days, and read afresh on every refresh so renamed fields and
    /// changed ranges show.
    private(set) var fields: [String: [TrackerFieldInfo]] = [:]
    /// Set by each refresh: the next fields read replaces the cache rather than adding to it.
    private var fieldsStale = false
    /// Bumped by each refresh, so a slower, older one cannot land over a newer one.
    private var summaryGeneration = 0
    /// Bumped by each timeline read (a refresh's or a day step's), for the same reason.
    private var dayGeneration = 0
    /// A refresh failed; what was showing stays.
    private(set) var refreshFailed = false
    /// The instant relative times are said against, taken afresh on every load.
    private(set) var now: Date

    private let home: HomeService
    private let trackersService: TrackersService
    private let clock: @MainActor () -> Date

    init(home: HomeService, trackers: TrackersService, clock: @escaping @MainActor () -> Date = Date.init) {
        self.home = home
        self.trackersService = trackers
        self.clock = clock
        let now = clock()
        self.now = now
        self.day = LocalDay(now, zone: .current)
    }

    // MARK: - What shows

    private var zone: TimeZone { receiver?.timeZone ?? .current }

    /// Today in the receiver's zone, read from the clock each time.
    var today: LocalDay { LocalDay(clock(), zone: zone) }

    var isShowingToday: Bool { day == today }

    /// The Today button sits with the date whenever the day shown is not today.
    var showsTodayButton: Bool { !isShowingToday }

    /// The stepper stops at today: forward is offered only behind it.
    var canStepForward: Bool { day < today }

    var hasActiveTrackers: Bool { trackers.contains { $0.status == .active } }

    var status: Status? {
        guard phase == .loaded else { return nil }
        if !hasActiveTrackers { return .noActiveTrackers }
        return attention.isEmpty ? .allClear : .needsAttention(attention)
    }

    /// Coming up is there only when something is coming (PRD "Coming up").
    var showsComingUp: Bool { phase == .loaded && !comingUp.isEmpty }

    /// Nothing logged and nothing came due: a first log or a note. With no active
    /// trackers there is nothing to log, so only the note (Figma 438:3971 / 438:4075).
    var dayOffers: [DayOffer] {
        guard case .loaded(let items) = dayPhase, items.isEmpty else { return [] }
        return hasActiveTrackers ? [.logAnEntry, .writeANote] : [.writeANote]
    }

    // MARK: - Loading

    /// Shows `receiver`. Someone new starts over on today; the same receiver, once
    /// loaded, refreshes in place on the day already showing (back from an entry, say).
    func show(_ receiver: TeamReceiver) async {
        if let current = self.receiver, current.id == receiver.id, phase == .loaded {
            self.receiver = receiver
            await refresh()
            return
        }
        self.receiver = receiver
        phase = .loading
        attention = []
        comingUp = []
        trackers = []
        fields = [:]
        refreshFailed = false
        day = LocalDay(clock(), zone: receiver.timeZone)
        dayPhase = .loading
        await loadAll()
    }

    /// Pull to refresh: the whole screen.
    func refresh() async {
        await loadAll()
    }

    /// Back from a Quick log run that saved something (PRD "Quick log" exits): the whole
    /// screen is read again, so a planning run's entries show under Coming up and a
    /// logging run's in the day — on the day they were logged, if Home was showing
    /// another, since a run's one time is today at the latest.
    func reflect(_ outcome: QuickLogModel.Outcome) async {
        guard outcome.savedAny, receiver != nil else { return }
        if !outcome.planning, let logged = outcome.latestDay, logged != day, logged <= today {
            day = logged
            dayPhase = .loading
        }
        await loadAll()
    }

    func retry() async {
        phase = .loading
        dayPhase = .loading
        await loadAll()
    }

    func retryDay() async {
        dayPhase = .loading
        await loadDay(day)
    }

    // MARK: - The day

    func stepBack() async {
        await go(to: day.adding(days: -1))
    }

    func stepForward() async {
        guard canStepForward else { return }
        await go(to: day.adding(days: 1))
    }

    func goToToday() async {
        await go(to: today)
    }

    /// What Jump to day's Done hands back. A day ahead of today is refused.
    func jump(to picked: LocalDay) async {
        guard picked <= today else { return }
        await go(to: picked)
    }

    private func go(to target: LocalDay) async {
        guard target != day || dayPhase == .failed else { return }
        day = target
        dayPhase = .loading
        await loadDay(target)
    }

    private func loadAll() async {
        guard let receiver else { return }
        summaryGeneration += 1
        dayGeneration += 1
        let summaryGen = summaryGeneration
        let dayGen = dayGeneration
        fieldsStale = true
        now = clock()
        let home = home
        let trackersService = trackersService
        let id = receiver.id
        let shown = day
        async let attentionResult = Self.capture { try await home.needsAttention(id, Self.sectionLimit) }
        async let comingUpResult = Self.capture { try await home.comingUp(id, Self.sectionLimit) }
        async let trackersResult = Self.capture { try await trackersService.listTrackers(id) }
        async let dayResult = Self.capture { try await home.dayTimeline(id, shown) }
        let (a, c, t, d) = await (attentionResult, comingUpResult, trackersResult, dayResult)

        guard self.receiver?.id == id else { return }
        if summaryGen == summaryGeneration {
            applySummary(a, c, t)
        }
        await apply(d, for: shown, receiverID: id, generation: dayGen)
    }

    private func applySummary(_ a: Result<[AttentionItem], Error>,
                              _ c: Result<[ReceiverEntryItem], Error>,
                              _ t: Result<[TrackerItem], Error>) {
        do {
            let (newAttention, newComingUp, newTrackers) = (try a.get(), try c.get(), try t.get())
            attention = newAttention
            comingUp = newComingUp
            trackers = newTrackers
            phase = .loaded
            refreshFailed = false
        } catch {
            if phase == .loaded {
                refreshFailed = true
            } else {
                phase = .failed(AppError.from(error))
            }
        }
    }

    private func loadDay(_ target: LocalDay) async {
        guard let receiver else { return }
        let home = home
        let id = receiver.id
        dayGeneration += 1
        let gen = dayGeneration
        let result = await Self.capture { try await home.dayTimeline(id, target) }
        await apply(result, for: target, receiverID: id, generation: gen)
    }

    /// Lands a timeline only if it is still the day and receiver showing, and no later
    /// read has started since.
    private func apply(_ result: Result<DayTimeline, Error>, for target: LocalDay, receiverID: String,
                       generation: Int) async {
        guard receiver?.id == receiverID, day == target, generation == dayGeneration else { return }
        switch result {
        case .success(let timeline):
            dayPhase = .loaded(timeline.items)
            await loadFields(for: timeline.items, generation: generation)
        case .failure:
            if case .loaded = dayPhase {
                refreshFailed = true
            } else {
                dayPhase = .failed
            }
        }
    }

    /// Reads the fields of each tracker on the day not already known — or, after a
    /// refresh, of every tracker on the day, replacing what was known.
    private func loadFields(for items: [DayItem], generation: Int) async {
        let replacing = fieldsStale
        var missing: [String] = []
        for item in items {
            if case .entry(let e) = item, replacing || fields[e.tracker.id] == nil,
               !missing.contains(e.tracker.id) {
                missing.append(e.tracker.id)
            }
        }
        guard !missing.isEmpty else {
            if replacing {
                fields = [:]
                fieldsStale = false
            }
            return
        }
        let service = trackersService
        let found = await withTaskGroup(of: (String, [TrackerFieldInfo]?).self) { group in
            for id in missing {
                group.addTask { (id, try? await service.trackerDetail(id).fields) }
            }
            var found: [String: [TrackerFieldInfo]] = [:]
            for await (id, list) in group {
                if let list { found[id] = list }
            }
            return found
        }
        guard generation == dayGeneration else { return }
        if replacing {
            fields = found
            fieldsStale = false
        } else {
            fields.merge(found) { _, new in new }
        }
    }

    private nonisolated static func capture<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

/// Jump to day — a month calendar that stops at today, as the stepper does (PRD "Jump to
/// day"). Picking a day selects it and stays; Done hands back the day picked. Pure.
struct JumpToDayModel: Equatable, Sendable {
    let today: LocalDay
    private(set) var month: CalendarMonth
    private(set) var selected: LocalDay

    /// Opens on the day Home is showing, in its month.
    init(today: LocalDay, showing: LocalDay) {
        self.today = today
        let start = min(showing, today)
        selected = start
        month = CalendarMonth(start)
    }

    var canGoForward: Bool { month < CalendarMonth(today) }

    mutating func goBack() { month = month.previous }

    mutating func goForward() {
        guard canGoForward else { return }
        month = month.next
    }

    func isDisabled(_ day: LocalDay) -> Bool { day > today }

    mutating func pick(_ day: LocalDay) {
        guard !isDisabled(day) else { return }
        selected = day
    }

    func state(of day: LocalDay) -> StrideCalendarDay.State {
        if day == selected { return .single }
        if isDisabled(day) { return .disabled }
        if day == today { return .today }
        return .default
    }
}
