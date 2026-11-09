import Foundation
import CaregiverAPI
import OpenAPIRuntime

/// A care receiver as the `/v1` API names them (`GET /v1/teams/{teamId}/receivers`).
/// Every wall-clock time about them is read in `timeZone` (PRD "Care receiver").
struct TeamReceiver: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let timeZone: TimeZone
    /// Whether the signed-in caregiver is an admin of the team this receiver is on, so
    /// may add, edit, pause and resume trackers and write their schedules. The API
    /// doesn't send it; whoever reaches the receiver sets it from `Account.teams[].role`
    /// (see `managed(by:)`), and every pushed screen reads it off the receiver it got.
    var canManage: Bool = false

    /// This receiver as seen by a caregiver with `team`'s role.
    func managed(by team: Account.Team) -> TeamReceiver {
        TeamReceiver(id: id, name: name, timeZone: timeZone, canManage: team.role == "admin")
    }
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
    let required: Bool
    let paused: Bool
    /// Numbers only; nil when it never alerts.
    let range: ValueRangeInfo?
    /// Choices only: several answers rather than one.
    let multiple: Bool
    let options: [ChoiceOptionInfo]

    init(id: String, label: String, kind: FieldKind, unit: String?, required: Bool = false,
         paused: Bool = false, range: ValueRangeInfo? = nil, multiple: Bool = false,
         options: [ChoiceOptionInfo]) {
        self.id = id
        self.label = label
        self.kind = kind
        self.unit = unit
        self.required = required
        self.paused = paused
        self.range = range
        self.multiple = multiple
        self.options = options
    }
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

/// One of a tracker's schedules (`TrackerSchedule`).
struct TrackerScheduleItem: Equatable, Identifiable, Sendable {
    let id: String
    /// The label, or the name the server derives when there is none.
    let name: String
    /// What an admin typed; nil when left blank.
    let label: String?
    let days: [ScheduleWeekday]
    /// In weeks.
    let interval: Int
    /// Local `HH:MM` in the receiver's time zone.
    let time: String
    /// Days in the receiver's time zone, as the API's `yyyy-MM-dd` dates. `startsOn` is
    /// only nil for fixtures that predate it; the API always sends one.
    let startsOn: LocalDay?
    let endsOn: LocalDay?
    /// Pre-filled values keyed by field id; a choice is its option ids.
    let plannedValues: [String: EntryValue]
    let unrecordedAlert: Bool

    init(id: String, name: String, label: String? = nil, days: [ScheduleWeekday], interval: Int,
         time: String, startsOn: LocalDay? = nil, endsOn: LocalDay? = nil,
         plannedValues: [String: EntryValue] = [:], unrecordedAlert: Bool) {
        self.id = id
        self.name = name
        self.label = label
        self.days = days
        self.interval = interval
        self.time = time
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.plannedValues = plannedValues
        self.unrecordedAlert = unrecordedAlert
    }
}

// MARK: - What the write calls send

/// A choice option as Add tracker or Edit tracker sends it (`ChoiceOptionWrite`).
struct OptionWrite: Equatable, Sendable {
    /// Nil for a new option.
    var optionID: String?
    var label: String
    var retired: Bool = false
}

/// A field as Add tracker or Edit tracker sends it (`TrackerFieldWrite`), and as a
/// template carries it (always without ids).
struct FieldWrite: Equatable, Sendable {
    /// Nil for a new field.
    var fieldID: String?
    var label: String
    var kind: FieldKind
    var unit: String?
    var required: Bool
    var paused: Bool = false
    var range: ValueRangeInfo?
    var multiple: Bool = false
    var options: [OptionWrite] = []
}

/// Name, icon, color, fields and gap — Add tracker's Create (`NewTracker`) and Edit
/// tracker's Save (`TrackerChanges`, less `remove_schedules`).
struct TrackerWrite: Equatable, Sendable {
    var name: String
    var icon: String
    var color: String
    /// Edit: every existing field by id, in order, plus new ones without one.
    var fields: [FieldWrite]
    /// Nil turns the gap off.
    var gapHours: Int?
}

/// A schedule's Save, new or changed (`NewSchedule` / `ScheduleWrite`, less `replace_gap`).
struct ScheduleWrite: Equatable, Sendable {
    /// Nil leaves the server to derive a name.
    var label: String?
    var days: [ScheduleWeekday]
    /// In weeks: 1, 2, 4 or 8.
    var interval: Int
    /// Local `HH:MM` in the receiver's time zone.
    var time: String
    var endsOn: LocalDay?
    /// Keyed by field id. A field nobody can know ahead is left out.
    var plannedValues: [String: EntryValue]
    var unrecordedAlert: Bool
}

/// One of the tracker templates Add tracker offers (`CatalogTemplate`).
struct TrackerTemplate: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let color: String
    /// Without ids; creating the tracker assigns them.
    let fields: [FieldWrite]
    let gapHours: Int?
}

/// The 409 `SchedulesOrGap`: a tracker has schedules or a gap, never both. Thrown by
/// `editTracker` (turning a gap on would remove every schedule) and `addSchedule` (the
/// first schedule would turn the gap off). Tell the admin what they will lose, then
/// resend with `removeSchedules` / `replaceGap` true.
struct SchedulesOrGapConflict: Error, Equatable {
    /// The server's wording; for logs, not for the screen.
    let message: String?
}

/// The `/v1` calls the Trackers area reads with, as closures so the models can be
/// tested without a network. Every non-OK answer is thrown as `AppError`.
struct TrackersService: Sendable {
    var listReceivers: @Sendable (_ teamID: String) async throws -> [TeamReceiver]
    var listTrackers: @Sendable (_ receiverID: String) async throws -> [TrackerItem]
    var trackerDetail: @Sendable (_ trackerID: String) async throws -> TrackerProfile
    var listEntries: @Sendable (_ trackerID: String, _ query: EntriesQuery) async throws -> EntriesPage
    var listSchedules: @Sendable (_ trackerID: String) async throws -> [TrackerScheduleItem]

    // Admin-only writes. Defaulted so a test or preview stubs only what it uses.
    var listTemplates: @Sendable () async throws -> [TrackerTemplate] = { throw Unstubbed() }
    var addTracker: @Sendable (_ receiverID: String, _ tracker: TrackerWrite) async throws -> TrackerProfile
        = { _, _ in throw Unstubbed() }
    /// Throws `SchedulesOrGapConflict` when a gap would remove schedules and `removeSchedules` is false.
    var editTracker: @Sendable (_ trackerID: String, _ changes: TrackerWrite, _ removeSchedules: Bool)
        async throws -> TrackerProfile = { _, _, _ in throw Unstubbed() }
    var pauseTracker: @Sendable (_ trackerID: String) async throws -> TrackerProfile = { _ in throw Unstubbed() }
    var resumeTracker: @Sendable (_ trackerID: String) async throws -> TrackerProfile = { _ in throw Unstubbed() }
    /// Throws `SchedulesOrGapConflict` on a gap-watched tracker while `replaceGap` is false.
    var addSchedule: @Sendable (_ trackerID: String, _ schedule: ScheduleWrite, _ replaceGap: Bool)
        async throws -> TrackerScheduleItem = { _, _, _ in throw Unstubbed() }
    var changeSchedule: @Sendable (_ scheduleID: String, _ schedule: ScheduleWrite)
        async throws -> TrackerScheduleItem = { _, _ in throw Unstubbed() }
    var removeSchedule: @Sendable (_ scheduleID: String) async throws -> Void = { _ in throw Unstubbed() }

    /// What a closure nobody stubbed throws.
    struct Unstubbed: Error {}

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
            },
            listTemplates: {
                switch try await client.listTemplates() {
                case .ok(let ok): return try ok.body.json.map(TrackerTemplate.init)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            addTracker: { receiverID, tracker in
                let output = try await client.addTracker(path: .init(receiverId: receiverID),
                                                         body: .json(tracker.newTracker))
                switch output {
                case .created(let created): return TrackerProfile(try created.body.json)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            editTracker: { trackerID, changes, removeSchedules in
                let output = try await client.editTracker(
                    path: .init(trackerId: trackerID),
                    body: .json(changes.trackerChanges(removeSchedules: removeSchedules))
                )
                switch output {
                case .ok(let ok): return TrackerProfile(try ok.body.json)
                case .conflict(let conflict): throw SchedulesOrGapConflict(message: try? conflict.body.json.message)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            pauseTracker: { trackerID in
                switch try await client.pauseTracker(path: .init(trackerId: trackerID)) {
                case .ok(let ok): return TrackerProfile(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            resumeTracker: { trackerID in
                switch try await client.resumeTracker(path: .init(trackerId: trackerID)) {
                case .ok(let ok): return TrackerProfile(try ok.body.json)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            addSchedule: { trackerID, schedule, replaceGap in
                let output = try await client.addSchedule(
                    path: .init(trackerId: trackerID),
                    body: .json(try schedule.newSchedule(replaceGap: replaceGap))
                )
                switch output {
                case .created(let created): return TrackerScheduleItem(try created.body.json)
                case .conflict(let conflict): throw SchedulesOrGapConflict(message: try? conflict.body.json.message)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            changeSchedule: { scheduleID, schedule in
                let output = try await client.changeSchedule(
                    path: .init(scheduleId: scheduleID),
                    body: .json(try schedule.scheduleWrite)
                )
                switch output {
                case .ok(let ok): return TrackerScheduleItem(try ok.body.json)
                case .badRequest(let bad): throw AppError.forStatus(400, serverMessage: try? bad.body.json.message)
                case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
                case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
                case .notFound: throw AppError.forStatus(404, serverMessage: nil)
                case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
                }
            },
            removeSchedule: { scheduleID in
                switch try await client.removeSchedule(path: .init(scheduleId: scheduleID)) {
                case .noContent: return
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

extension ValueRangeInfo {
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
                    required: f.required, paused: f.status == .paused,
                    range: f.range.map { ValueRangeInfo($0) }, multiple: f.multiple ?? false,
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

extension FieldKind {
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
        self.init(id: e.entryId, state: state, at: e.at, values: EntryValue.map(e.values.additionalProperties),
                  note: e.note, byName: e.byName)
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
        self.init(id: s.scheduleId, name: s.name, label: s.label,
                  days: s.rule.byDay.compactMap { ScheduleWeekday(rawValue: $0.rawValue) }.sorted(),
                  interval: s.rule.interval, time: s.time,
                  startsOn: LocalDay(dayString: s.startsOn), endsOn: s.endsOn.flatMap(LocalDay.init(dayString:)),
                  plannedValues: EntryValue.map(s.plannedValues.additionalProperties),
                  unrecordedAlert: s.unrecordedAlert)
    }
}

extension EntryValue {
    /// Every value of a free-form JSON object the app can read, keyed as sent.
    static func map(_ object: OpenAPIObjectContainer) -> [String: EntryValue] {
        var values: [String: EntryValue] = [:]
        for (key, raw) in object.value {
            if let value = raw.flatMap(EntryValue.init(raw:)) { values[key] = value }
        }
        return values
    }

    /// This value as `OpenAPIObjectContainer` takes it: a number, a string, a bool, or a
    /// list of option ids.
    var jsonValue: any Sendable {
        switch self {
        case .number(let d): d
        case .string(let s): s
        case .bool(let b): b
        case .list(let ids): ids.map { $0 as (any Sendable)? }
        }
    }

    /// `values` as a free-form JSON object.
    static func object(_ values: [String: EntryValue]) throws -> OpenAPIObjectContainer {
        try OpenAPIObjectContainer(unvalidatedValue: values.mapValues { $0.jsonValue as (any Sendable)? })
    }
}

extension LocalDay {
    /// Reads a `yyyy-MM-dd` date; nil for anything else.
    init?(dayString: String) {
        let parts = dayString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }
}

// MARK: - Mapping to the generated types

extension Components.Schemas.FieldKind {
    init(_ k: FieldKind) {
        switch k {
        case .number: self = .number
        case .text: self = .text
        case .boolean: self = .boolean
        case .choice: self = .choice
        case .datetime: self = .datetime
        }
    }
}

extension FieldWrite {
    init(_ f: Components.Schemas.TrackerFieldWrite) {
        self.init(fieldID: f.fieldId, label: f.label, kind: FieldKind(f._type), unit: f.unit,
                  required: f.required, paused: f.status == .paused, range: f.range.map { ValueRangeInfo($0) },
                  multiple: f.multiple ?? false,
                  options: (f.options ?? []).map {
                      OptionWrite(optionID: $0.optionId, label: $0.label, retired: $0.status == .retired)
                  })
    }

    var generated: Components.Schemas.TrackerFieldWrite {
        Components.Schemas.TrackerFieldWrite(
            fieldId: fieldID, label: label, _type: .init(kind),
            unit: kind == .number ? unit : nil,
            required: required, status: paused ? .paused : .active,
            range: kind == .number ? range.map { .init(low: $0.low, high: $0.high) } : nil,
            multiple: kind == .choice ? multiple : nil,
            options: kind == .choice
                ? options.map { .init(optionId: $0.optionID, label: $0.label, status: $0.retired ? .retired : .active) }
                : nil
        )
    }
}

extension TrackerTemplate {
    init(_ t: Components.Schemas.CatalogTemplate) {
        self.init(id: t.templateId, name: t.name, icon: t.icon, color: t.color,
                  fields: t.fields.map(FieldWrite.init), gapHours: t.gapHours)
    }
}

extension TrackerWrite {
    var newTracker: Components.Schemas.NewTracker {
        .init(name: name, icon: icon, color: color, fields: fields.map(\.generated), gapHours: gapHours)
    }

    func trackerChanges(removeSchedules: Bool) -> Components.Schemas.TrackerChanges {
        .init(name: name, icon: icon, color: color, fields: fields.map(\.generated), gapHours: gapHours,
              removeSchedules: removeSchedules ? true : nil)
    }
}

extension ScheduleWrite {
    var rule: Components.Schemas.Recurrence {
        .init(freq: .weekly, interval: interval,
              byDay: days.sorted().compactMap { Components.Schemas.Weekday(rawValue: $0.rawValue) })
    }

    func newSchedule(replaceGap: Bool) throws -> Components.Schemas.NewSchedule {
        .init(label: label, rule: rule, time: time, endsOn: endsOn?.dayString,
              plannedValues: .init(additionalProperties: try EntryValue.object(plannedValues)),
              unrecordedAlert: unrecordedAlert, replaceGap: replaceGap ? true : nil)
    }

    var scheduleWrite: Components.Schemas.ScheduleWrite {
        get throws {
            .init(label: label, rule: rule, time: time, endsOn: endsOn?.dayString,
                  plannedValues: .init(additionalProperties: try EntryValue.object(plannedValues)),
                  unrecordedAlert: unrecordedAlert)
        }
    }
}
