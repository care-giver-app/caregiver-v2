import Foundation
import OpenAPIRuntime

/// Every sentence Quick log's run says, as constants and pure functions.
enum QuickLogText {
    static let journalNote = "Journal note"
    static let earlierTodayProblem = "Choose a time earlier today."
    static let futureProblem = "Choose a time in the future."
    static let nothingToPlan = "Journal notes and waiting care can't be planned. Go back and pick a tracker."
    static let noteRequired = "Write the note."
    static let notInState = "Someone settled this first, or its tracker was paused. Nothing was saved for it."
    static let trackerPaused = "This tracker was paused, so nothing was saved for it."
    /// A new entry or note whose request went out but whose answer never came back: it
    /// may have saved, and sending it again could record it twice.
    static let outcomeUnknown = "Couldn't tell whether this saved. Check Home before logging it again."
    /// Raised from Tracker detail on a tracker paused since.
    static let scopedTrackerPaused = "This tracker is paused, so there's nothing to log on it."
    /// Raised from Tracker detail on a tracker deleted since.
    static let scopedTrackerGone = "This tracker is no longer here, so there's nothing to log on it."

    static func noteTooLong(_ max: Int) -> String { "Keep the note to \(max) characters or fewer." }

    // MARK: The sheet's words (Figma section 5 · Quick log, 448:4146)

    static let pickHeading = "What to record"
    static let whenHeading = "When did it happen?"
    static let waitingLabel = "WAITING"
    static let trackersLabel = "TRACKERS"
    static let addTracker = "Add a tracker"
    static let now = "Now"
    static let earlierToday = "Earlier today"
    static let futureTime = "A future time"
    static let pickATime = "Pick a time"
    static let planIt = "Plan it"
    static let oneTime = "One time for everything you picked."
    static let planningCaption = "This plans entries instead of logging them. Journal notes can't be planned."
    static let alertIfUnrecorded = "Alert if it goes unrecorded"
    static let plannedStepCaption = "Fill in what you already know. The rest is left for whoever logs it."
    static let resultsLabel = "RESULTS"
    static let couldNotSave = "Couldn't save"
    static let saved = "Saved"
    static let loadFailed = "Couldn't load what there is to record."
    static let fieldsFailed = "Couldn't load the trackers' fields."
    static let noReceiver = "There's no one to record for yet. Care receivers are added on Team."

    /// "STEP 2 OF 3", "STEP 1 OF 2 · PLANNING".
    static func stepLabel(_ index: Int, of count: Int, planning: Bool) -> String {
        "STEP \(index + 1) OF \(count)" + (planning ? " · PLANNING" : "")
    }

    /// "3 saved", "2 of 3 saved", "2 planned" (Figma 448:4542, 448:4583).
    static func resultsHeading(saved: Int, of count: Int, planning: Bool) -> String {
        let verb = planning ? "planned" : "saved"
        return saved == count ? "\(count) \(verb)" : "\(saved) of \(count) \(verb)"
    }

    /// A waiting occurrence: its schedule and time — "Morning · 8:00 AM" today, with the
    /// day when it is not today: "Evening · Yesterday at 8:00 PM".
    static func occurrenceLine(_ entry: TrackerEntry, now: Date, zone: TimeZone) -> String {
        guard LocalDay(entry.at, zone: zone) != LocalDay(now, zone: zone) else {
            return HomeText.itemTime(entry, zone: zone)
        }
        let when = HomeText.entryWhen(entry.at, now: now, zone: zone)
        guard let schedule = entry.scheduleName, !schedule.isEmpty else { return when }
        return "\(schedule) · \(when)"
    }

    /// What one line of the result says under its title: a plan's time; what became of
    /// a waiting occurrence ("Morning · skipped"); "Logged", "Saved", or "Couldn't save".
    static func resultLine(_ result: QuickLogModel.Result, planning: Bool, now: Date, zone: TimeZone) -> String {
        switch result.status {
        case .failed:
            return couldNotSave
        case .savedNote:
            return saved
        case .savedEntry(let d):
            if planning { return HomeText.entryWhen(d.entry.at, now: now, zone: zone) }
            let state = TrackerText.stateLabel(d.entry.state)
            if case .occurrence = result.item, let schedule = d.entry.scheduleName, !schedule.isEmpty {
                return "\(schedule) · \(state.lowercased())"
            }
            return state
        }
    }
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
        /// Raised from Tracker detail on a tracker no longer active: this line, and Cancel.
        case nothingToLog(String)
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
        /// A failure worth trying again: not one the server refused for the entry's state,
        /// nor a new entry or note that may have saved already.
        var retryable = false
        /// A failure that may have saved all the same: a create whose answer was lost, or a
        /// log or skip refused on a retry because the first attempt landed.
        var mightHaveSaved = false

        var id: Item { item }

        var saved: Bool {
            if case .failed = status { return false }
            return true
        }
    }

    /// What the run's caller needs once it is done.
    struct Outcome: Equatable, Sendable {
        /// Whose run it was.
        let receiverID: String
        /// A planning run's entries sit under Coming up; a logging run's in the day behind it.
        let planning: Bool
        /// The latest day, in the receiver's zone, anything saved belongs to; nil if nothing saved.
        let latestDay: LocalDay?
        /// Whether anything saved, or may have, so Home, Entry detail or Tracker detail refreshes.
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
    /// Failed lines of the result being saved again.
    private(set) var retrying: Set<Item> = []
    /// Add a tracker was taken: Quick log is dismissed and Add tracker takes its place.
    private(set) var wantsAddTracker = false

    private let home: HomeService
    private let trackers: TrackersService
    private let clock: @MainActor () -> Date

    /// `clock` is the server's, as near as the phone can tell (`ServerClock`): the server
    /// refuses a time more than a minute ahead of its own.
    init(start: QuickLogStart, receiver: TeamReceiver, home: HomeService, trackers: TrackersService,
         clock: @escaping @MainActor () -> Date = { ServerClock.shared.now() }) {
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
                activeTrackers = active.filter { $0.id == id }
                // Paused or deleted since Tracker detail was read: nothing here can be saved.
                guard !activeTrackers.isEmpty else {
                    let paused = allTrackers.contains { $0.id == id }
                    hasPickingPart = false
                    part = .nothingToLog(paused ? QuickLogText.scopedTrackerPaused : QuickLogText.scopedTrackerGone)
                    return
                }
                waiting = allWaiting.filter { $0.tracker.id == id }
                // Nothing waiting to pick between: straight to when, with the tracker picked.
                if waiting.isEmpty {
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
        // than plan, and an earlier time is no longer today once midnight has passed in
        // the receiver's zone: back to when, which now says so.
        if when != .now, !whenProblems.isEmpty {
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

    /// `retried`: a log or skip being sent again after a failure that may have landed.
    private func save(_ item: Item, now: Date, retried: Bool = false) async -> Result {
        let d = draft(for: item)
        let at = runTime(now: now)
        switch item {
        case .journalNote:
            do {
                let note = try await home.addJournalNote(
                    receiver.id, NoteWrite(at: at, body: d.note.trimmingCharacters(in: .whitespacesAndNewlines)))
                return Result(item: item, title: QuickLogText.journalNote, tracker: nil, status: .savedNote(note))
            } catch {
                return Self.createFailure(item, title: QuickLogText.journalNote, badge: nil, error)
            }
        case .tracker(let id):
            let tracker = activeTrackers.first { $0.id == id }
            let badge = tracker.map { TrackerBadgeInfo(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color) }
            // Now is left to the server's clock, so a phone running fast cannot turn a
            // log into a plan.
            let write = NewEntryWrite(at: when == .now ? nil : at, values: d.values.sent(for: activeFields(id)),
                                      note: d.note, unrecordedAlert: isPlanning && alertIfUnrecorded)
            return await entryResult(item, title: tracker?.name ?? "", badge: badge, paused: QuickLogText.trackerPaused,
                                     creates: true) {
                try await self.home.addEntry(id, write)
            }
        case .occurrence(let id):
            guard let o = occurrence(id) else {
                return Result(item: item, title: "", tracker: nil, status: .failed(QuickLogText.notInState))
            }
            if d.choice == .skip {
                let note = d.note
                return await entryResult(item, title: o.tracker.name, badge: o.tracker, paused: QuickLogText.notInState,
                                         retried: retried) {
                    try await self.home.skipEntry(id, note)
                }
            }
            let care = EntryCareWrite(occurredAt: at, values: d.values.sent(for: activeFields(o.tracker.id)), note: d.note)
            return await entryResult(item, title: o.tracker.name, badge: o.tracker, paused: QuickLogText.notInState,
                                     retried: retried) {
                try await self.home.logEntry(id, care)
            }
        }
    }

    /// `creates`: a new entry, which sending twice would record twice. Logging or
    /// skipping a waiting one is safe to send again: a second attempt after the first
    /// landed is refused with a 409. That 409 on a `retried` write is kept as it reads —
    /// nothing was saved by it — but the line may have saved the first time.
    private func entryResult(_ item: Item, title: String, badge: TrackerBadgeInfo?, paused: String,
                             creates: Bool = false, retried: Bool = false,
                             _ write: () async throws -> EntryDetailInfo) async -> Result {
        do {
            return Result(item: item, title: title, tracker: badge, status: .savedEntry(try await write()))
        } catch is EntryNotInState {
            return Result(item: item, title: title, tracker: badge, status: .failed(paused), mightHaveSaved: retried)
        } catch {
            if creates { return Self.createFailure(item, title: title, badge: badge, error) }
            return Result(item: item, title: title, tracker: badge, status: .failed(AppError.from(error).message),
                          retryable: true)
        }
    }

    /// A new entry or journal note that failed. One sent whose answer never came back may
    /// have saved: it is said so, and not offered again.
    private static func createFailure(_ item: Item, title: String, badge: TrackerBadgeInfo?, _ error: Error) -> Result {
        if mayHaveLanded(error) {
            return Result(item: item, title: title, tracker: badge, status: .failed(QuickLogText.outcomeUnknown),
                          mightHaveSaved: true)
        }
        return Result(item: item, title: title, tracker: badge, status: .failed(AppError.from(error).message),
                      retryable: true)
    }

    /// Whether a failed request may have reached the server and been carried out: it went
    /// out but no answer came back (a timeout, a dropped connection), or an answer came
    /// that could not be read. A refusal with a status, or a failure to connect at all,
    /// saved nothing.
    nonisolated static func mayHaveLanded(_ error: Error) -> Bool {
        if error is AppError || error is EntryNotInState || error is CancellationError { return false }
        if let client = error as? ClientError {
            if client.response != nil { return true }
            return mayHaveLanded(client.underlyingError)
        }
        guard let url = error as? URLError else { return false }
        switch url.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .badURL, .unsupportedURL,
             .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return false
        default:
            return true
        }
    }

    /// The result's Retry (Figma 448:4570): one failed line saved again, as it was entered.
    /// A plan whose time has come since cannot be saved as a plan, and is said so.
    func retry(_ item: Item) async {
        guard part == .result, let i = results.firstIndex(where: { $0.item == item }),
              results[i].retryable, !retrying.contains(item) else { return }
        let earlier = results[i]
        retrying.insert(item)
        defer { retrying.remove(item) }
        let now = clock()
        let result: Result
        if isPlanning, futureTime <= now.addingTimeInterval(Self.futureMargin) {
            result = Result(item: earlier.item, title: earlier.title, tracker: earlier.tracker,
                            status: .failed(QuickLogText.futureProblem))
        } else {
            result = await save(item, now: now, retried: true)
        }
        if let j = results.firstIndex(where: { $0.item == item }) { results[j] = result }
    }

    /// The run's one time as it stands: now, the earlier time, or the future time.
    func runTime(now: Date) -> Date {
        switch when {
        case .now: now
        case .earlierToday: earlierTime
        case .future: futureTime
        }
    }

    /// Saving the run, or a line of its result again: the sheet stays up until it is done,
    /// so how the run ended is read once nothing more can land.
    var isSaving: Bool { part == .submitting || !retrying.isEmpty }

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
        return Outcome(receiverID: receiver.id, planning: isPlanning, latestDay: days.max(),
                       savedAny: !days.isEmpty || results.contains(where: \.mightHaveSaved))
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
