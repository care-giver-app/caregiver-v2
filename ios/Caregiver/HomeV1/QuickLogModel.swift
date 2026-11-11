import Foundation

/// Every sentence Quick log's run says, as constants and pure functions.
enum QuickLogText {
    static let journalNote = "Journal note"
    static let earlierTodayProblem = "Choose a time earlier today."
    static let futureProblem = "Choose a time in the future."
    static let nothingToPlan = "Journal notes and waiting care can't be planned. Go back and pick a tracker."
    static let noteRequired = "Write the note."
    static let notInState = "Someone settled this first, or its tracker was paused. Nothing was saved for it."
    static let trackerPaused = "This tracker was paused, so nothing was saved for it."

    static func noteTooLong(_ max: Int) -> String { "Keep the note to \(max) characters or fewer." }
}

/// Quick log (PRD "The tab bar", "Quick log"): one sheet that runs in three parts — what
/// to record, when it happened, then a step for each thing picked — and ends on a result
/// reporting item by item. A run given a future time is planning rather than logging.
///
/// The model knows nothing of the screens; Quick log's sheet draws `part`.
@MainActor
@Observable
final class QuickLogModel {
    /// One thing a caregiver can pick.
    enum Item: Hashable, Sendable {
        /// A waiting occurrence: logged or skipped.
        case occurrence(entryID: String)
        /// A tracker: logged ad hoc, or planned.
        case tracker(id: String)
        case journalNote
    }

    enum Part: Equatable {
        case loading
        case loadFailed(AppError)
        /// What to record.
        case pick
        /// When it happened, asked once for the whole run.
        case when
        /// One picked item's step, an index into `steps`.
        case step(Int)
        case submitting
        case result
    }

    /// The run's one time.
    enum When: Equatable, Sendable {
        case now
        /// `earlierTime`: a time today, in the receiver's zone, not after now.
        case earlierToday
        /// `futureTime`: planning.
        case future
    }

    /// What has been entered for one item, kept until it is dropped from the picker.
    struct Draft: Equatable, Sendable {
        var values = EntryValuesDraft()
        /// The entry's note, or a journal note's body.
        var note = ""
        /// Occurrences only.
        var choice: OccurrenceChoice = .logIt
    }

    /// One step of the run, with what its screen needs.
    enum Step: Equatable {
        /// `fields` are the active ones, in the tracker's order.
        case tracker(TrackerItem, fields: [TrackerFieldInfo])
        case occurrence(ReceiverEntryItem, fields: [TrackerFieldInfo])
        case journalNote
    }

    /// One line of the result.
    struct Result: Equatable, Identifiable {
        enum Status: Equatable {
            case savedEntry(EntryDetailInfo)
            case savedNote(JournalNoteInfo)
            case failed(String)
        }

        let item: Item
        /// The tracker's name, or "Journal note".
        let title: String
        /// Nil for a journal note.
        let tracker: TrackerBadgeInfo?
        let status: Status

        var id: Item { item }

        var saved: Bool {
            if case .failed = status { return false }
            return true
        }
    }

    /// What the run's caller needs once it is done.
    struct Outcome: Equatable {
        /// A planning run's entries sit under Coming up; a logging run's in the day behind it.
        let planning: Bool
        /// The latest day, in the receiver's zone, anything saved belongs to; nil if nothing saved.
        let latestDay: LocalDay?
        /// Whether anything saved, so Home, Entry detail or Tracker detail refreshes.
        let savedAny: Bool
    }

    /// Server bound: a journal note's body.
    static let maxJournalNote = 5000
    /// How far ahead a future time must be. The server takes anything within a minute of
    /// its clock as now and would log it rather than plan it.
    static let futureMargin: TimeInterval = 60

    let start: QuickLogStart
    let receiver: TeamReceiver

    private(set) var part: Part
    /// Whether the run has a picking part to step back to: not when raised from Entry
    /// detail, nor from Tracker detail with nothing waiting to pick between.
    private(set) var hasPickingPart: Bool

    /// Occurrences waiting, in the API's order: unrecorded first. Scoped to one tracker
    /// when raised from Tracker detail.
    private(set) var waiting: [ReceiverEntryItem] = []
    /// The receiver's active trackers, in the API's order; just the one when scoped.
    private(set) var activeTrackers: [TrackerItem] = []

    /// In the order they were picked; the steps follow it.
    private(set) var picked: [Item] = []
    private var drafts: [Item: Draft] = [:]
    /// Each tracker's fields, paused ones included, read on the way into the steps.
    private var fields: [String: [TrackerFieldInfo]] = [:]
    /// Entry detail's entry, which may not be among the waiting.
    private var heldEntry: ReceiverEntryItem?

    var when: When = .now
    var earlierTime: Date
    var futureTime: Date
    /// Planning only: tell the team if the care goes unrecorded.
    var alertIfUnrecorded = false

    /// Reading the picked trackers' fields on the way into the steps.
    private(set) var isLoadingFields = false
    private(set) var fieldsFailed: AppError?

    private(set) var results: [Result] = []
    /// Add a tracker was taken: Quick log is dismissed and Add tracker takes its place.
    private(set) var wantsAddTracker = false

    private let home: HomeService
    private let trackers: TrackersService
    private let clock: @MainActor () -> Date

    init(start: QuickLogStart, receiver: TeamReceiver, home: HomeService, trackers: TrackersService,
         clock: @escaping @MainActor () -> Date = Date.init) {
        self.start = start
        self.receiver = receiver
        self.home = home
        self.trackers = trackers
        self.clock = clock
        let now = clock()
        earlierTime = Self.defaultEarlier(now: now, zone: receiver.timeZone)
        futureTime = Self.defaultFuture(now: now, zone: receiver.timeZone)

        switch start {
        case .entry(let detail, let choice):
            let item = Item.occurrence(entryID: detail.entry.id)
            hasPickingPart = false
            part = .step(0)
            heldEntry = ReceiverEntryItem(tracker: detail.tracker, entry: detail.entry)
            fields = [detail.tracker.id: detail.fields]
            picked = [item]
            drafts = [item: Draft(values: EntryValuesDraft(detail.entry.values), choice: choice)]
        case .journalNote:
            hasPickingPart = true
            part = .loading
            picked = [.journalNote]
        case .pick, .tracker:
            hasPickingPart = true
            part = .loading
        }
    }

    // MARK: - Loading

    /// Reads what the picker holds. Raised from Entry detail there is nothing to read.
    func load() async {
        if case .entry = start { return }
        part = .loading
        do {
            async let waitingRead = home.waiting(receiver.id)
            async let trackersRead = trackers.listTrackers(receiver.id)
            let (allWaiting, allTrackers) = try await (waitingRead, trackersRead)
            let active = allTrackers.filter { $0.status == .active }
            if case .tracker(let id) = start {
                waiting = allWaiting.filter { $0.tracker.id == id }
                activeTrackers = active.filter { $0.id == id }
                // Nothing waiting to pick between: straight to when, with the tracker picked.
                if waiting.isEmpty, !activeTrackers.isEmpty {
                    picked = [.tracker(id: id)]
                    hasPickingPart = false
                    part = .when
                    return
                }
            } else {
                waiting = allWaiting
                activeTrackers = active
            }
            part = .pick
        } catch {
            part = .loadFailed(AppError.from(error))
        }
    }

    // MARK: - What to record

    var isPlanning: Bool { when == .future }

    private var isScoped: Bool {
        if case .tracker = start { return true }
        return false
    }

    /// The picker's occurrences: none on a future time, as there is nothing to plan about a plan.
    var pickerOccurrences: [ReceiverEntryItem] { isPlanning ? [] : waiting }

    var pickerTrackers: [TrackerItem] { activeTrackers }

    /// A journal note cannot be planned, and a run scoped to one tracker offers only it.
    var offersJournalNote: Bool { !isScoped && !isPlanning }

    /// Admins are always offered a new tracker, whatever else the picker holds.
    var offersAddTracker: Bool { !isScoped && receiver.canManage }

    /// What a caregiver who is not an admin is told when there is nothing to log against.
    var noTrackersLine: String? {
        !isScoped && activeTrackers.isEmpty && !receiver.canManage ? HomeText.noTrackersCaregiverLine : nil
    }

    func isPicked(_ item: Item) -> Bool { picked.contains(item) }

    /// Picks an item, or drops it along with whatever was entered for it.
    func toggle(_ item: Item) {
        if let i = picked.firstIndex(of: item) {
            picked.remove(at: i)
            drafts[item] = nil
        } else {
            picked.append(item)
        }
    }

    /// Ends the run for Add tracker. Admins only.
    func chooseAddTracker() {
        guard offersAddTracker else { return }
        wantsAddTracker = true
    }

    /// What the run holds now, in pick order: on a future time, only trackers — journal
    /// notes and waiting occurrences leave it, and come back if the time does.
    var selection: [Item] {
        picked.filter { item in
            if case .tracker = item { return true }
            return !isPlanning
        }
    }

    var canContinueFromPick: Bool { !selection.isEmpty }

    func continueFromPick() {
        guard part == .pick, canContinueFromPick else { return }
        part = .when
    }

    // MARK: - When

    /// A future time is not offered to a run holding one waiting entry: it cannot be planned.
    var offersFuture: Bool {
        if case .entry = start { return false }
        return true
    }

    /// The receiver's today, against which an earlier time is checked.
    var today: LocalDay { LocalDay(clock(), zone: receiver.timeZone) }

    var whenProblems: [String] {
        let now = clock()
        switch when {
        case .now:
            return []
        case .earlierToday:
            let sameDay = LocalDay(earlierTime, zone: receiver.timeZone) == LocalDay(now, zone: receiver.timeZone)
            return sameDay && earlierTime <= now ? [] : [QuickLogText.earlierTodayProblem]
        case .future:
            var out: [String] = []
            if !offersFuture || futureTime <= now.addingTimeInterval(Self.futureMargin) {
                out.append(QuickLogText.futureProblem)
            }
            if selection.isEmpty { out.append(QuickLogText.nothingToPlan) }
            return out
        }
    }

    /// Reads the fields the steps need, then goes to the first step.
    func continueFromWhen() async {
        guard part == .when, whenProblems.isEmpty, !selection.isEmpty, !isLoadingFields else { return }
        isLoadingFields = true
        fieldsFailed = nil
        defer { isLoadingFields = false }
        do {
            try await loadFields()
            part = .step(0)
        } catch {
            fieldsFailed = AppError.from(error)
        }
    }

    private func loadFields() async throws {
        var needed: [String] = []
        for item in selection {
            guard let id = trackerID(of: item), fields[id] == nil, !needed.contains(id) else { continue }
            needed.append(id)
        }
        guard !needed.isEmpty else { return }
        let service = trackers
        let read = try await withThrowingTaskGroup(of: (String, [TrackerFieldInfo]).self) { group in
            for id in needed {
                group.addTask { (id, try await service.trackerDetail(id).fields) }
            }
            var out: [String: [TrackerFieldInfo]] = [:]
            for try await (id, f) in group { out[id] = f }
            return out
        }
        fields.merge(read) { _, new in new }
    }

    // MARK: - Steps

    var steps: [Step] { selection.compactMap(step(for:)) }

    func step(for item: Item) -> Step? {
        switch item {
        case .tracker(let id):
            guard let tracker = activeTrackers.first(where: { $0.id == id }) else { return nil }
            return .tracker(tracker, fields: activeFields(id))
        case .occurrence(let id):
            guard let occurrence = occurrence(id) else { return nil }
            return .occurrence(occurrence, fields: activeFields(occurrence.tracker.id))
        case .journalNote:
            return .journalNote
        }
    }

    /// What has been entered for `item`; a picked occurrence starts pre-filled from its plan.
    func draft(for item: Item) -> Draft {
        if let d = drafts[item] { return d }
        if case .occurrence(let id) = item, let o = occurrence(id) {
            return Draft(values: EntryValuesDraft(o.entry.values))
        }
        return Draft()
    }

    func updateDraft(_ item: Item, _ change: (inout Draft) -> Void) {
        guard picked.contains(item) else { return }
        var d = draft(for: item)
        change(&d)
        drafts[item] = d
    }

    /// What stops a step going on. A logged tracker or occurrence must answer every
    /// required active field; planning pre-fills and requires nothing; a skip takes only
    /// a note.
    func problems(for item: Item) -> [String] {
        let d = draft(for: item)
        var out: [String] = []
        switch item {
        case .journalNote:
            let body = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { out.append(QuickLogText.noteRequired) }
            if body.count > Self.maxJournalNote { out.append(QuickLogText.noteTooLong(Self.maxJournalNote)) }
            return out
        case .tracker(let id):
            out = d.values.problems(for: activeFields(id), requireAll: !isPlanning)
        case .occurrence(let id):
            if d.choice == .logIt, let o = occurrence(id) {
                out = d.values.problems(for: activeFields(o.tracker.id), requireAll: true)
            }
        }
        if d.note.count > EntryValuesDraft.maxNote { out.append(QuickLogText.noteTooLong(EntryValuesDraft.maxNote)) }
        return out
    }

    var isLastStep: Bool {
        if case .step(let i) = part { return i == selection.count - 1 }
        return false
    }

    /// The next step, or — from the last — saving the run.
    func advance() async {
        guard case .step(let i) = part, selection.indices.contains(i),
              problems(for: selection[i]).isEmpty else { return }
        if i < selection.count - 1 {
            part = .step(i + 1)
        } else {
            await submit()
        }
    }

    var canGoBack: Bool {
        switch part {
        case .when: hasPickingPart
        case .step: true
        default: false
        }
    }

    /// One step or part back, with what was entered still there.
    func back() {
        switch part {
        case .when where hasPickingPart:
            part = .pick
        case .step(let i):
            part = i > 0 ? .step(i - 1) : .when
        default:
            break
        }
    }

    // MARK: - Saving

    /// One request per item, in pick order, every one attempted; the result reports each.
    func submit() async {
        let items = selection
        guard !items.isEmpty else { return }
        if let i = items.firstIndex(where: { !problems(for: $0).isEmpty }) {
            part = .step(i)
            return
        }
        let now = clock()
        // A future time that has come while the steps were filled in would log rather
        // than plan: back to when, which now says so.
        if isPlanning, futureTime <= now.addingTimeInterval(Self.futureMargin) {
            part = .when
            return
        }
        part = .submitting
        var out: [Result] = []
        for item in items {
            out.append(await save(item, now: now))
        }
        results = out
        part = .result
    }

    private func save(_ item: Item, now: Date) async -> Result {
        let d = draft(for: item)
        let at: Date = switch when {
        case .now: now
        case .earlierToday: earlierTime
        case .future: futureTime
        }
        switch item {
        case .journalNote:
            do {
                let note = try await home.addJournalNote(
                    receiver.id, NoteWrite(at: at, body: d.note.trimmingCharacters(in: .whitespacesAndNewlines)))
                return Result(item: item, title: QuickLogText.journalNote, tracker: nil, status: .savedNote(note))
            } catch {
                return Result(item: item, title: QuickLogText.journalNote, tracker: nil,
                              status: .failed(AppError.from(error).message))
            }
        case .tracker(let id):
            let tracker = activeTrackers.first { $0.id == id }
            let badge = tracker.map { TrackerBadgeInfo(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color) }
            // Now is left to the server's clock, so a phone running fast cannot turn a
            // log into a plan.
            let write = NewEntryWrite(at: when == .now ? nil : at, values: d.values.sent(for: activeFields(id)),
                                      note: d.note, unrecordedAlert: isPlanning && alertIfUnrecorded)
            return await entryResult(item, title: tracker?.name ?? "", badge: badge, paused: QuickLogText.trackerPaused) {
                try await self.home.addEntry(id, write)
            }
        case .occurrence(let id):
            guard let o = occurrence(id) else {
                return Result(item: item, title: "", tracker: nil, status: .failed(QuickLogText.notInState))
            }
            if d.choice == .skip {
                let note = d.note
                return await entryResult(item, title: o.tracker.name, badge: o.tracker, paused: QuickLogText.notInState) {
                    try await self.home.skipEntry(id, note)
                }
            }
            let care = EntryCareWrite(occurredAt: at, values: d.values.sent(for: activeFields(o.tracker.id)), note: d.note)
            return await entryResult(item, title: o.tracker.name, badge: o.tracker, paused: QuickLogText.notInState) {
                try await self.home.logEntry(id, care)
            }
        }
    }

    private func entryResult(_ item: Item, title: String, badge: TrackerBadgeInfo?, paused: String,
                             _ write: () async throws -> EntryDetailInfo) async -> Result {
        do {
            return Result(item: item, title: title, tracker: badge, status: .savedEntry(try await write()))
        } catch is EntryNotInState {
            return Result(item: item, title: title, tracker: badge, status: .failed(paused))
        } catch {
            return Result(item: item, title: title, tracker: badge, status: .failed(AppError.from(error).message))
        }
    }

    /// Set once the run has ended on its result.
    var outcome: Outcome? {
        guard part == .result else { return nil }
        let days = results.compactMap { r -> LocalDay? in
            switch r.status {
            case .savedEntry(let d): LocalDay(d.entry.at, zone: receiver.timeZone)
            case .savedNote(let n): LocalDay(n.at, zone: receiver.timeZone)
            case .failed: nil
            }
        }
        return Outcome(planning: isPlanning, latestDay: days.max(), savedAny: !days.isEmpty)
    }

    // MARK: - Lookups

    private func occurrence(_ entryID: String) -> ReceiverEntryItem? {
        if let held = heldEntry, held.entry.id == entryID { return held }
        return waiting.first { $0.entry.id == entryID }
    }

    private func trackerID(of item: Item) -> String? {
        switch item {
        case .tracker(let id): id
        case .occurrence(let id): occurrence(id)?.tracker.id
        case .journalNote: nil
        }
    }

    private func activeFields(_ trackerID: String) -> [TrackerFieldInfo] {
        (fields[trackerID] ?? []).filter { !$0.paused }
    }

    // MARK: - Default times

    /// An hour ago, but never before midnight.
    static func defaultEarlier(now: Date, zone: TimeZone) -> Date {
        max(LocalDay(now, zone: zone).start(in: zone), now.addingTimeInterval(-3600))
    }

    /// The first whole hour at least an hour ahead.
    static func defaultFuture(now: Date, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let ahead = now.addingTimeInterval(3600)
        let hour = calendar.dateInterval(of: .hour, for: ahead)!
        return hour.start == ahead ? ahead : hour.end
    }
}
