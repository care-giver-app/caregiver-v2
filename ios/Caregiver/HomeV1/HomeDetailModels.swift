import Foundation

/// One read behind a pushed Home screen — Coming up, Entry detail, Journal note. The
/// first load fills the screen; every load after it is a refresh that keeps what is
/// showing and says so if it fails, except a 404, which means the thing is gone (deleted
/// elsewhere) and is said as such rather than offered a retry.
@MainActor
@Observable
final class HomeReadModel<Value: Equatable & Sendable> {
    enum Phase: Equatable {
        case loading
        case loaded(Value)
        case gone
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading
    /// A refresh of what was loaded failed; it stays.
    private(set) var refreshFailed = false
    /// The instant relative times are said against, taken afresh on every load.
    private(set) var now: Date

    private let fetch: @Sendable () async throws -> Value
    private let clock: @MainActor () -> Date

    init(clock: @escaping @MainActor () -> Date = Date.init,
         fetch: @escaping @Sendable () async throws -> Value) {
        self.fetch = fetch
        self.clock = clock
        self.now = clock()
    }

    var value: Value? {
        if case .loaded(let v) = phase { return v }
        return nil
    }

    func load() async {
        do {
            let value = try await fetch()
            now = clock()
            phase = .loaded(value)
            refreshFailed = false
        } catch {
            let error = AppError.from(error)
            if error.isNotFound {
                phase = .gone
            } else if value != nil {
                refreshFailed = true
            } else {
                phase = .failed(error)
            }
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// What a write on this screen answered with — Edit entry's Save, or Delete leaving
    /// an entry waiting again — shown as it now stands without reading it again.
    func replace(with value: Value) {
        now = clock()
        phase = .loaded(value)
        refreshFailed = false
    }
}

extension HomeReadModel where Value == [ReceiverEntryItem] {
    /// Coming up in full: each tracker's next scheduled entry, soonest first, no limit.
    static func comingUp(_ receiverID: String, home: HomeService,
                         clock: @escaping @MainActor () -> Date = Date.init) -> HomeReadModel {
        HomeReadModel(clock: clock) { try await home.comingUp(receiverID, nil) }
    }
}

extension HomeReadModel where Value == EntryDetailInfo {
    static func entry(_ entryID: String, home: HomeService,
                      clock: @escaping @MainActor () -> Date = Date.init) -> HomeReadModel {
        HomeReadModel(clock: clock) { try await home.entry(entryID) }
    }
}

extension HomeReadModel where Value == JournalNoteInfo {
    static func note(_ noteID: String, home: HomeService,
                     clock: @escaping @MainActor () -> Date = Date.init) -> HomeReadModel {
        HomeReadModel(clock: clock) { try await home.journalNote(noteID) }
    }
}

/// A label and its value, as Entry detail and Journal note list them.
struct DetailRow: Equatable, Sendable {
    let label: String
    let value: String
    /// Nothing given yet — a pre-filled entry's field left for whoever logs it.
    var pending = false
    /// "Expected 90–140" when the value fell outside its range.
    var expected: String? = nil
}

/// What Entry detail offers, by the entry's state rather than by where it was opened
/// from (PRD "Entry detail"). Log it and Skip open Quick log; Edit raises Edit entry and
/// Delete raises Delete this entry?, both as sheets over Entry detail.
enum EntryOffer: Equatable, Sendable {
    case logIt, skip, edit, delete

    static func offers(for state: EntryState) -> [EntryOffer] {
        switch state {
        case .scheduled, .unrecorded: [.logIt, .skip]
        case .logged, .skipped: [.edit, .delete]
        }
    }
}

/// Everything Entry detail says about one entry, worked out from `EntryDetailInfo`
/// (PRD "Entry detail"; Figma 445:4161, 445:4210, 445:4263, 445:4326). Times are in the
/// receiver's zone.
struct EntryDetailContent: Equatable {
    enum Callout: Equatable {
        /// One sentence per value outside its range.
        case outOfRange([String])
        /// Unrecorded care still in needs attention.
        case unrecorded
    }

    /// How long unrecorded care stays in needs attention (PRD "Home").
    static let unrecordedAttentionWindow: TimeInterval = 48 * 3600

    let tracker: TrackerBadgeInfo
    let state: EntryState
    /// "Today at 8:00 PM".
    let when: String
    let callout: Callout?
    /// "PRE-FILLED" before the entry is settled, "FIELDS" after; nil with no rows.
    let fieldsTitle: String?
    let fields: [DetailRow]
    let note: String?
    /// The schedule it came from, who logged or skipped it, who changed it last.
    let details: [DetailRow]
    let offers: [EntryOffer]

    init(_ d: EntryDetailInfo, now: Date, zone: TimeZone) {
        let entry = d.entry
        tracker = d.tracker
        state = entry.state
        when = HomeText.entryWhen(entry.at, now: now, zone: zone)
        offers = EntryOffer.offers(for: entry.state)

        let outside = Dictionary(d.outOfRange.map { ($0.fieldID, $0) }, uniquingKeysWith: { a, _ in a })
        let settled = entry.state == .logged || entry.state == .skipped

        // Every field the entry holds a value for, paused ones included, in the tracker's
        // order. Before it is settled, an active field with nothing pre-filled is shown as
        // left for whoever logs it — but only when something at all was pre-filled.
        var rows: [DetailRow] = []
        var anyValue = false
        for field in d.fields {
            if let raw = entry.values[field.id],
               let text = TrackerText.value(raw, field: field, now: now, zone: zone) {
                anyValue = true
                rows.append(DetailRow(label: field.label, value: text,
                                      expected: outside[field.id].map { HomeText.expectedUnderValue($0.range) }))
            } else if !settled, !field.paused {
                rows.append(DetailRow(label: field.label, value: HomeText.leftForLogger, pending: true))
            }
        }
        fields = anyValue ? rows : []
        fieldsTitle = fields.isEmpty ? nil : (settled ? "FIELDS" : "PRE-FILLED")

        switch entry.state {
        case .logged where !d.outOfRange.isEmpty:
            callout = .outOfRange(d.outOfRange.map { o in
                let field = d.fields.first { $0.id == o.fieldID }
                return HomeText.outOfRangeSentence(label: field?.label ?? "Reading", value: o.value,
                                                   unit: field?.unit, range: o.range)
            })
        case .unrecorded
            where now.timeIntervalSince(d.occurrenceAt ?? entry.at) < Self.unrecordedAttentionWindow:
            callout = .unrecorded
        default:
            callout = nil
        }

        note = entry.note.flatMap { $0.isEmpty ? nil : $0 }

        var details: [DetailRow] = []
        if let schedule = entry.scheduleName, !schedule.isEmpty {
            details.append(DetailRow(label: "Schedule", value: schedule))
        }
        if settled, let by = HomeText.whoAndWhen(entry.byName, at: d.settledAt, about: entry.at,
                                                  now: now, zone: zone) {
            details.append(DetailRow(label: entry.state == .logged ? "Logged by" : "Skipped by", value: by))
        }
        if let name = d.updatedByName, let at = d.updatedAt,
           let changed = HomeText.whoAndWhen(name, at: at, about: entry.at, now: now, zone: zone) {
            details.append(DetailRow(label: "Changed by", value: changed))
        }
        self.details = details
    }
}

/// Everything Journal note says about one note (PRD "Journal note"; Figma 447:4245).
struct JournalNoteContent: Equatable {
    /// The time it is about.
    let when: String
    let body: String
    /// Who wrote it, and who changed it last if anyone has.
    let details: [DetailRow]

    init(_ n: JournalNoteInfo, now: Date, zone: TimeZone) {
        when = TrackerText.when(n.at, now: now, zone: zone)
        body = n.body
        var details: [DetailRow] = []
        if let written = HomeText.whoAndWhen(n.authorName, at: n.createdAt, about: n.at, now: now, zone: zone) {
            details.append(DetailRow(label: "Written by", value: written))
        }
        if let name = n.updatedByName, let at = n.updatedAt,
           let changed = HomeText.whoAndWhen(name, at: at, about: n.at, now: now, zone: zone) {
            details.append(DetailRow(label: "Changed by", value: changed))
        }
        self.details = details
    }
}
