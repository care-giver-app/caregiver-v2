import Foundation
import CaregiverAPI

/// A care receiver as the `/v1` API names them (`GET /v1/teams/{teamId}/receivers`).
/// Every wall-clock time about them is read in `timeZone` (PRD "Care receiver").
struct TeamReceiver: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let timeZone: TimeZone
}

enum TrackerStatus: Equatable, Hashable, Sendable {
    case active, paused
}

/// One row of the Trackers list (`TrackerRow`).
struct TrackerItem: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// An SF Symbol name.
    let icon: String
    /// `#RRGGBB`.
    let color: String
    let status: TrackerStatus
    let lastLoggedAt: Date?
    let pausedAt: Date?
    /// Always false when paused.
    let needsAttention: Bool
}

enum FieldKind: Equatable, Sendable {
    case number, text, boolean, choice, datetime
}

struct ChoiceOptionInfo: Equatable, Sendable {
    let id: String
    let label: String
    let retired: Bool
}

struct ValueRangeInfo: Equatable, Sendable {
    let low: Double?
    let high: Double?
}

/// A field a tracker captures (`TrackerField`), paused or not.
struct TrackerFieldInfo: Equatable, Sendable {
    let id: String
    let label: String
    let kind: FieldKind
    let unit: String?
    let options: [ChoiceOptionInfo]
}

/// One thing wrong with a tracker right now (`TrackerAttention`).
enum TrackerAttentionItem: Equatable, Sendable {
    case unrecorded(occurrenceAt: Date)
    case outOfRange(fieldID: String, value: Double, range: ValueRangeInfo)
    case gap(since: Date, gapHours: Int)
}

/// Tracker detail's header (`TrackerDetail`).
struct TrackerProfile: Equatable, Sendable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let status: TrackerStatus
    let pausedAt: Date?
    /// Every field it has ever had, paused ones included, in order.
    let fields: [TrackerFieldInfo]
    let gapHours: Int?
    let scheduleCount: Int
    let lastLoggedAt: Date?
    let attention: [TrackerAttentionItem]
}

enum EntryState: Equatable, Sendable {
    case scheduled, unrecorded, logged, skipped
}

/// One stored value, before the tracker's field says how to read it.
enum EntryValue: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    /// A choice: the chosen option ids.
    case list([String])
}

struct TrackerEntry: Equatable, Identifiable, Sendable {
    let id: String
    let state: EntryState
    /// When the care happened if logged, otherwise when it was due.
    let at: Date
    /// Keyed by field id.
    let values: [String: EntryValue]
    let note: String?
    /// Who logged or skipped it; nil while unrecorded.
    let byName: String?
}

struct EntriesPage: Equatable, Sendable {
    let entries: [TrackerEntry]
    /// Nil on the last page.
    let nextCursor: String?
}

/// `from` / `to` are `yyyy-MM-dd` dates in the receiver's time zone, inclusive.
struct EntriesQuery: Equatable, Sendable {
    var from: String?
    var to: String?
    var cursor: String?
}

enum ScheduleWeekday: String, CaseIterable, Comparable, Sendable {
    case mo = "MO", tu = "TU", we = "WE", th = "TH", fr = "FR", sa = "SA", su = "SU"

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One of a tracker's schedules (`TrackerSchedule`), as Schedules reads it.
struct TrackerScheduleItem: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let days: [ScheduleWeekday]
    /// In weeks.
    let interval: Int
    /// Local `HH:MM` in the receiver's time zone.
    let time: String
    let unrecordedAlert: Bool
}

/// The `/v1` calls the Trackers area reads with, as closures so the models can be
/// tested without a network. Every non-OK answer is thrown as `AppError`.
struct TrackersService: Sendable {
    var listReceivers: @Sendable (_ teamID: String) async throws -> [TeamReceiver]
    var listTrackers: @Sendable (_ receiverID: String) async throws -> [TrackerItem]
    var trackerDetail: @Sendable (_ trackerID: String) async throws -> TrackerProfile
    var listEntries: @Sendable (_ trackerID: String, _ query: EntriesQuery) async throws -> EntriesPage
    var listSchedules: @Sendable (_ trackerID: String) async throws -> [TrackerScheduleItem]

    static func live(_ client: Client) -> TrackersService {
        TrackersService(
            listReceivers: { teamID in
                switch try await client.listTeamReceivers(path: .init(teamId: teamID)) {
                case .ok(let ok): return try ok.body.json.map(TeamReceiver.init)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            listTrackers: { receiverID in
                switch try await client.listReceiverTrackers(path: .init(receiverId: receiverID)) {
                case .ok(let ok): return try ok.body.json.map(TrackerItem.init)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            trackerDetail: { trackerID in
                switch try await client.getTrackerDetail(path: .init(trackerId: trackerID)) {
                case .ok(let ok): return TrackerProfile(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            listEntries: { trackerID, query in
                let output = try await client.listTrackerEntries(
                    path: .init(trackerId: trackerID),
                    query: .init(from: query.from, to: query.to, cursor: query.cursor)
                )
                switch output {
                case .ok(let ok):
                    let page = try ok.body.json
                    return EntriesPage(entries: page.entries.map(TrackerEntry.init), nextCursor: page.nextCursor)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            listSchedules: { trackerID in
                switch try await client.listTrackerSchedules(path: .init(trackerId: trackerID)) {
                case .ok(let ok): return try ok.body.json.map(TrackerScheduleItem.init)
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

extension TeamReceiver {
    init(_ r: Components.Schemas.CareReceiver) {
        // An unknown zone name should never happen; GMT keeps the screen readable if it does.
        self.init(id: r.receiverId, name: r.name,
                  timeZone: TimeZone(identifier: r.timeZone) ?? TimeZone(secondsFromGMT: 0)!)
    }
}

private extension TrackerStatus {
    init(_ s: Components.Schemas.TrackerStatus) {
        self = s == .paused ? .paused : .active
    }
}

extension TrackerItem {
    init(_ r: Components.Schemas.TrackerRow) {
        self.init(id: r.trackerId, name: r.name, icon: r.icon, color: r.color,
                  status: TrackerStatus(r.status), lastLoggedAt: r.lastLoggedAt,
                  pausedAt: r.pausedAt, needsAttention: r.needsAttention)
    }
}

private extension ValueRangeInfo {
    init(_ r: Components.Schemas.ValueRange?) {
        self.init(low: r?.low, high: r?.high)
    }
}

extension TrackerProfile {
    init(_ d: Components.Schemas.TrackerDetail) {
        self.init(
            id: d.trackerId, name: d.name, icon: d.icon, color: d.color,
            status: TrackerStatus(d.status), pausedAt: d.pausedAt,
            fields: d.fields.map { f in
                TrackerFieldInfo(
                    id: f.fieldId, label: f.label, kind: FieldKind(f._type), unit: f.unit,
                    options: (f.options ?? []).map {
                        ChoiceOptionInfo(id: $0.optionId, label: $0.label, retired: $0.status == .retired)
                    }
                )
            },
            gapHours: d.gapHours, scheduleCount: d.scheduleCount, lastLoggedAt: d.lastLoggedAt,
            attention: d.attention.compactMap(TrackerAttentionItem.init)
        )
    }
}

private extension FieldKind {
    init(_ k: Components.Schemas.FieldKind) {
        switch k {
        case .number: self = .number
        case .text: self = .text
        case .boolean: self = .boolean
        case .choice: self = .choice
        case .datetime: self = .datetime
        }
    }
}

private extension TrackerAttentionItem {
    /// Nil when the server left out what a kind needs — nothing true can be said then.
    init?(_ a: Components.Schemas.TrackerAttention) {
        switch a.kind {
        case .unrecorded:
            guard let at = a.occurrenceAt else { return nil }
            self = .unrecorded(occurrenceAt: at)
        case .outOfRange:
            guard let field = a.fieldId, let value = a.value else { return nil }
            self = .outOfRange(fieldID: field, value: value, range: ValueRangeInfo(a.range))
        case .gap:
            guard let since = a.since, let hours = a.gapHours else { return nil }
            self = .gap(since: since, gapHours: hours)
        }
    }
}

extension TrackerEntry {
    init(_ e: Components.Schemas.Entry) {
        let state: EntryState = switch e.state {
        case .scheduled: .scheduled
        case .unrecorded: .unrecorded
        case .logged: .logged
        case .skipped: .skipped
        }
        var values: [String: EntryValue] = [:]
        for (key, raw) in e.values.additionalProperties.value {
            if let value = raw.flatMap(EntryValue.init(raw:)) { values[key] = value }
        }
        self.init(id: e.entryId, state: state, at: e.at, values: values, note: e.note, byName: e.byName)
    }
}

extension EntryValue {
    /// Reads one JSON value as decoded by `OpenAPIObjectContainer`.
    init?(raw: any Sendable) {
        switch raw {
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .number(Double(i))
        case let d as Double: self = .number(d)
        case let s as String: self = .string(s)
        case let list as [(any Sendable)?]: self = .list(list.compactMap { $0 as? String })
        default: return nil
        }
    }
}

extension TrackerScheduleItem {
    init(_ s: Components.Schemas.TrackerSchedule) {
        self.init(id: s.scheduleId, name: s.name,
                  days: s.rule.byDay.compactMap { ScheduleWeekday(rawValue: $0.rawValue) }.sorted(),
                  interval: s.rule.interval, time: s.time, unrecordedAlert: s.unrecordedAlert)
    }
}
