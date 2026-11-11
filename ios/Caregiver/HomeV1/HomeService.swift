import Foundation
import CaregiverAPI
import OpenAPIRuntime

/// Enough of a tracker to draw its row (`TrackerBadge`), for lists that mix trackers.
struct TrackerBadgeInfo: Equatable, Hashable, Sendable {
    let id: String
    let name: String
    /// An SF Symbol name.
    let icon: String
    /// `#RRGGBB`.
    let color: String
}

/// One thing wrong with a tracker right now, as Home's needs attention lists it, with
/// what each kind leads to (PRD "Needs attention").
enum NeedsAttention: Equatable, Sendable {
    /// Care whose time has passed with nothing logged or skipped; leads to the waiting entry.
    case unrecorded(entryID: String, occurrenceAt: Date)
    /// A latest reading outside its field's range; leads to the entry that carries it.
    case outOfRange(entryID: String, fieldID: String, fieldLabel: String?, unit: String?,
                    value: Double, range: ValueRangeInfo)
    /// Longer than `gapHours` since `since`; there is no entry, so it leads to the tracker.
    case gap(since: Date, gapHours: Int)
}

/// One row of needs attention (`AttentionItem`).
struct AttentionItem: Equatable, Sendable {
    let tracker: TrackerBadgeInfo
    let attention: NeedsAttention
}

/// An entry with its tracker (`ReceiverEntry`), for Coming up and the timeline.
struct ReceiverEntryItem: Equatable, Identifiable, Sendable {
    let tracker: TrackerBadgeInfo
    let entry: TrackerEntry

    var id: String { entry.id }
}

/// A journal note (`JournalNote`).
struct JournalNoteInfo: Equatable, Identifiable, Sendable {
    let id: String
    let receiverID: String
    /// The time it is about.
    let at: Date
    let body: String
    /// Who wrote it, or "a former caregiver".
    let authorName: String
    let createdAt: Date
    /// Who changed it last; nil if it has never been changed.
    let updatedByName: String?
    let updatedAt: Date?
}

/// One line of a day's timeline (`TimelineItem`): an entry with its tracker, or a note.
enum DayItem: Equatable, Identifiable, Sendable {
    case entry(ReceiverEntryItem)
    case note(JournalNoteInfo)

    var id: String {
        switch self {
        case .entry(let e): "entry-\(e.entry.id)"
        case .note(let n): "note-\(n.id)"
        }
    }

    var at: Date {
        switch self {
        case .entry(let e): e.entry.at
        case .note(let n): n.at
        }
    }
}

/// One day of one care receiver, oldest first (`DayTimeline`). Empty `items` is the
/// day where nothing was logged and nothing came due.
struct DayTimeline: Equatable, Sendable {
    /// A day in the receiver's time zone.
    let day: LocalDay
    let items: [DayItem]
}

/// One logged number outside its field's range as the range stands now (`OutOfRange`).
struct OutOfRangeInfo: Equatable, Sendable {
    let fieldID: String
    let value: Double
    let range: ValueRangeInfo
}

/// Everything Entry detail shows (`EntryDetail`).
struct EntryDetailInfo: Equatable, Sendable {
    let entry: TrackerEntry
    let tracker: TrackerBadgeInfo
    /// The tracker's fields, paused ones included, so every value can be labeled.
    let fields: [TrackerFieldInfo]
    /// It fulfils a plan, so deleting it leaves the occurrence waiting again.
    let planned: Bool
    /// When it was due; planned entries only.
    let occurrenceAt: Date?
    /// Planned entries only.
    let unrecordedAlert: Bool?
    /// When it was logged or skipped (the act, not the care); nil while waiting.
    let settledAt: Date?
    let updatedByName: String?
    let updatedAt: Date?
    /// Empty unless logged.
    let outOfRange: [OutOfRangeInfo]
}

/// The `/v1` reads Home is drawn from, as closures so the models can be tested without
/// a network. Every non-OK answer is thrown as `AppError`.
struct HomeService: Sendable {
    var needsAttention: @Sendable (_ receiverID: String, _ limit: Int?) async throws -> [AttentionItem]
    var comingUp: @Sendable (_ receiverID: String, _ limit: Int?) async throws -> [ReceiverEntryItem]
    /// `day` is in the receiver's time zone, no later than today there.
    var dayTimeline: @Sendable (_ receiverID: String, _ day: LocalDay) async throws -> DayTimeline
    var entry: @Sendable (_ entryID: String) async throws -> EntryDetailInfo
    var journalNote: @Sendable (_ noteID: String) async throws -> JournalNoteInfo

    static func live(_ client: Client) -> HomeService {
        HomeService(
            needsAttention: { receiverID, limit in
                let output = try await client.listNeedsAttention(path: .init(receiverId: receiverID),
                                                                 query: .init(limit: limit))
                switch output {
                case .ok(let ok): return try ok.body.json.compactMap(AttentionItem.init)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            comingUp: { receiverID, limit in
                let output = try await client.listComingUp(path: .init(receiverId: receiverID),
                                                           query: .init(limit: limit))
                switch output {
                case .ok(let ok): return try ok.body.json.map(ReceiverEntryItem.init)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            dayTimeline: { receiverID, day in
                let output = try await client.getDayTimeline(path: .init(receiverId: receiverID),
                                                             query: .init(date: day.dayString))
                switch output {
                case .ok(let ok): return DayTimeline(try ok.body.json, asked: day)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            entry: { entryID in
                switch try await client.getEntry(path: .init(entryId: entryID)) {
                case .ok(let ok): return EntryDetailInfo(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            journalNote: { noteID in
                switch try await client.getJournalNote(path: .init(noteId: noteID)) {
                case .ok(let ok): return JournalNoteInfo(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            }
        )
    }
}

// MARK: - Mapping from the generated types

extension TrackerBadgeInfo {
    init(_ b: Components.Schemas.TrackerBadge) {
        self.init(id: b.trackerId, name: b.name, icon: b.icon, color: b.color)
    }
}

extension AttentionItem {
    /// Nil when the server left out what a kind needs — nothing true can be said then.
    init?(_ a: Components.Schemas.AttentionItem) {
        let t = a.attention
        let attention: NeedsAttention
        switch t.kind {
        case .unrecorded:
            guard let entry = t.entryId, let at = t.occurrenceAt else { return nil }
            attention = .unrecorded(entryID: entry, occurrenceAt: at)
        case .outOfRange:
            guard let entry = t.entryId, let field = t.fieldId, let value = t.value else { return nil }
            attention = .outOfRange(entryID: entry, fieldID: field, fieldLabel: a.fieldLabel, unit: a.unit,
                                    value: value, range: ValueRangeInfo(t.range))
        case .gap:
            guard let since = t.since, let hours = t.gapHours else { return nil }
            attention = .gap(since: since, gapHours: hours)
        }
        self.init(tracker: TrackerBadgeInfo(a.tracker), attention: attention)
    }
}

extension ReceiverEntryItem {
    init(_ r: Components.Schemas.ReceiverEntry) {
        self.init(tracker: TrackerBadgeInfo(r.tracker), entry: TrackerEntry(r.entry))
    }
}

extension JournalNoteInfo {
    init(_ n: Components.Schemas.JournalNote) {
        self.init(id: n.noteId, receiverID: n.receiverId, at: n.at, body: n.body, authorName: n.authorName,
                  createdAt: n.createdAt, updatedByName: n.updatedByName, updatedAt: n.updatedAt)
    }
}

extension DayItem {
    /// Nil when `kind` names a part the server left out.
    init?(_ i: Components.Schemas.TimelineItem) {
        switch i.kind {
        case .entry:
            guard let tracker = i.tracker, let entry = i.entry else { return nil }
            self = .entry(ReceiverEntryItem(tracker: TrackerBadgeInfo(tracker), entry: TrackerEntry(entry)))
        case .note:
            guard let note = i.note else { return nil }
            self = .note(JournalNoteInfo(note))
        }
    }
}

extension DayTimeline {
    /// `asked` stands in should the server's `date` ever not read as one.
    init(_ t: Components.Schemas.DayTimeline, asked: LocalDay) {
        self.init(day: LocalDay(dayString: t.date) ?? asked, items: t.items.compactMap(DayItem.init))
    }
}

extension EntryDetailInfo {
    init(_ d: Components.Schemas.EntryDetail) {
        self.init(
            entry: TrackerEntry(d.entry), tracker: TrackerBadgeInfo(d.tracker),
            fields: d.fields.map(TrackerFieldInfo.init), planned: d.planned,
            occurrenceAt: d.occurrenceAt, unrecordedAlert: d.unrecordedAlert, settledAt: d.settledAt,
            updatedByName: d.updatedByName, updatedAt: d.updatedAt,
            outOfRange: d.outOfRange.map {
                OutOfRangeInfo(fieldID: $0.fieldId, value: $0.value, range: ValueRangeInfo($0.range))
            }
        )
    }
}
