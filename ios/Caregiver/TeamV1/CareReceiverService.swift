import Foundation
import CaregiverAPI
import OpenAPIRuntime

/// A wall-clock time on a day in the receiver's time zone — the API's `YYYY-MM-DDTHH:MM`.
/// No zone is ever applied to it; it is already the receiver's.
struct LocalDateTime: Hashable, Comparable, Sendable {
    let day: LocalDay
    /// Local `HH:MM`.
    let time: String

    init(day: LocalDay, time: String) {
        self.day = day
        self.time = time
    }

    /// Nil unless `s` is `YYYY-MM-DDTHH:MM`.
    init?(_ s: String) {
        let parts = s.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, let day = LocalDay(dayString: String(parts[0])),
              LocalDateTime.isTime(String(parts[1])) else { return nil }
        self.init(day: day, time: String(parts[1]))
    }

    var string: String { "\(day.dayString)T\(time)" }

    var minutes: Int { LocalDateTime.minutes(time) ?? 0 }

    static func < (a: LocalDateTime, b: LocalDateTime) -> Bool {
        (a.day, a.minutes) < (b.day, b.minutes)
    }

    /// `HH:MM`, 00:00 to 23:59.
    static func isTime(_ s: String) -> Bool { minutes(s) != nil }

    static func minutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard s.count == 5, parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// The local time `date` reads as in `zone`.
    init(_ date: Date, zone: TimeZone) {
        self.init(day: LocalDay(date, zone: zone), time: TrackerText.format(date, "HH:mm", zone))
    }
}

/// The care instructions — one free-form document — and who last changed it
/// (`CareInstructions`). The stamp covers the written body alone.
struct CareInstructionsInfo: Equatable, Sendable {
    let body: String
    /// Who last changed the written instructions, or "a former caregiver".
    let updatedByName: String
    let updatedAt: Date
}

/// One emergency contact (`EmergencyContact`).
struct EmergencyContactInfo: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let relationship: String
    /// As the admin typed it; the app dials it.
    let phone: String
}

/// Everything Care receiver shows that is not coverage (`CareReceiverDetail`).
struct CareReceiverInfo: Equatable, Sendable {
    let id: String
    let teamID: String
    let teamName: String
    let name: String
    let timeZone: TimeZone
    let isArchived: Bool
    /// While archived: who archived them and when, when the server says.
    let archivedByName: String?
    let archivedAt: Date?
    /// Nil when none have been written.
    let instructions: CareInstructionsInfo?
    /// In the order the admin set.
    let contacts: [EmergencyContactInfo]

    /// Enough of them to push or pick, as seen by a caregiver with `canManage`.
    func receiver(canManage: Bool) -> TeamReceiver {
        TeamReceiver(id: id, name: name, timeZone: timeZone, canManage: canManage)
    }
}

/// One span of time one caregiver is responsible for a receiver (`Assignment`).
struct AssignmentInfo: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let receiverID: String
    let userID: String
    /// Who is responsible, or "a former caregiver".
    let caregiverName: String
    let starts: LocalDateTime
    let ends: LocalDateTime
    let startsAt: Date
    let endsAt: Date
    /// The rule that made it; nil if made, or since changed, by hand.
    let coverageScheduleID: String?
}

/// One recurring rule that makes assignments (`CoverageSchedule`).
struct CoverageScheduleInfo: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let receiverID: String
    let userID: String
    let caregiverName: String
    let days: [ScheduleWeekday]
    /// In weeks.
    let interval: Int
    /// Local `HH:MM`; an end earlier than the start runs past midnight.
    let startTime: String
    let endTime: String
    let startsOn: LocalDay?
    let endsOn: LocalDay?
}

/// One contact in Emergency contacts' Save, in the order they should appear.
struct EmergencyContactWrite: Equatable, Sendable {
    /// Keeps an existing contact; nil for a new one.
    let contactID: String?
    let name: String
    let relationship: String
    let phone: String
}

/// An assignment's Save (`AssignmentWrite`).
struct AssignmentWrite: Equatable, Sendable {
    let userID: String
    let starts: LocalDateTime
    let ends: LocalDateTime
}

/// A coverage schedule's Save (`CoverageScheduleWrite`).
struct CoverageScheduleWrite: Equatable, Sendable {
    let userID: String
    let days: [ScheduleWeekday]
    let interval: Int
    let startTime: String
    let endTime: String
    let endsOn: LocalDay?
}

/// A write that answers nothing worth keeping (`204`).
struct Done: Equatable, Sendable {}

/// How a write about a care receiver answered.
enum ReceiverWriteOutcome<Value: Sendable>: Sendable {
    case done(Value)
    /// 409 — the receiver is archived, and everything about them is read-only until an
    /// admin restores them. For an assignment it may instead mean it has already ended.
    case refused
    /// 400 — with the server's message, when it sent one.
    case rejected(String?)
}

extension ReceiverWriteOutcome: Equatable where Value: Equatable {}

// MARK: - The calls

extension TeamService {
    /// Care receiver's reads and writes on the `/v1` client.
    func withReceiver(_ client: Client) -> TeamService {
        var s = self
        s.careReceiver = { receiverID in
            switch try await client.getCareReceiver(path: .init(receiverId: receiverID)) {
            case .ok(let ok): return CareReceiverInfo(try ok.body.json)
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.changeReceiver = { receiverID, name, zone in
            switch try await client.changeCareReceiver(path: .init(receiverId: receiverID),
                                                       body: .json(.init(name: name, timeZone: zone.identifier))) {
            case .ok(let ok): return .done(TeamReceiver(try ok.body.json))
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.archiveReceiver = { receiverID in
            switch try await client.archiveCareReceiver(path: .init(receiverId: receiverID)) {
            case .noContent: return
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.restoreReceiver = { receiverID in
            switch try await client.restoreCareReceiver(path: .init(receiverId: receiverID)) {
            case .noContent: return
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.changeInstructions = { receiverID, body in
            switch try await client.changeCareInstructions(path: .init(receiverId: receiverID),
                                                           body: .json(.init(body: body))) {
            case .ok(let ok): return .done(CareReceiverInfo(try ok.body.json))
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.changeContacts = { receiverID, contacts in
            let body = Components.Schemas.EmergencyContactsWrite(contacts: contacts.map {
                .init(contactId: $0.contactID, name: $0.name, relationship: $0.relationship, phone: $0.phone)
            })
            switch try await client.changeEmergencyContacts(path: .init(receiverId: receiverID), body: .json(body)) {
            case .ok(let ok): return .done(CareReceiverInfo(try ok.body.json))
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.onDuty = { receiverID in try await Self.onDuty(client, receiverID) }
        s.assignments = { receiverID in
            switch try await client.listAssignmentsAhead(path: .init(receiverId: receiverID)) {
            case .ok(let ok): return try ok.body.json.compactMap(AssignmentInfo.init)
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.addAssignment = { receiverID, write in
            switch try await client.addAssignment(path: .init(receiverId: receiverID), body: .json(write.schema)) {
            case .created(let created): return try Self.assignment(created.body.json)
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.changeAssignment = { assignmentID, write in
            switch try await client.changeAssignment(path: .init(assignmentId: assignmentID),
                                                     body: .json(write.schema)) {
            case .ok(let ok): return try Self.assignment(ok.body.json)
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.removeAssignment = { assignmentID in
            switch try await client.removeAssignment(path: .init(assignmentId: assignmentID)) {
            case .noContent: return .done(Done())
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.coverageSchedules = { receiverID in
            switch try await client.listCoverageSchedules(path: .init(receiverId: receiverID)) {
            case .ok(let ok): return try ok.body.json.map(CoverageScheduleInfo.init)
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.addCoverage = { receiverID, write in
            switch try await client.addCoverageSchedule(path: .init(receiverId: receiverID),
                                                        body: .json(write.schema)) {
            case .created(let created): return .done(CoverageScheduleInfo(try created.body.json))
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.changeCoverage = { scheduleID, write in
            switch try await client.changeCoverageSchedule(path: .init(coverageScheduleId: scheduleID),
                                                           body: .json(write.schema)) {
            case .ok(let ok): return .done(CoverageScheduleInfo(try ok.body.json))
            case .badRequest(let bad): return .rejected(try? bad.body.json.message)
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        s.removeCoverage = { scheduleID in
            switch try await client.removeCoverageSchedule(path: .init(coverageScheduleId: scheduleID)) {
            case .noContent: return .done(Done())
            case .conflict: return .refused
            case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
            case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
            case .notFound: throw AppError.forStatus(404, serverMessage: nil)
            case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
            }
        }
        return s
    }

    /// `GET /v1/receivers/{id}/on-duty` — Care receiver's and Home's.
    static func onDuty(_ client: Client, _ receiverID: String) async throws -> [AssignmentInfo] {
        switch try await client.listOnDuty(path: .init(receiverId: receiverID)) {
        case .ok(let ok): return try ok.body.json.compactMap(AssignmentInfo.init)
        case .unauthorized: throw AppError.forStatus(401, serverMessage: nil)
        case .forbidden: throw AppError.forStatus(403, serverMessage: nil)
        case .notFound: throw AppError.forStatus(404, serverMessage: nil)
        case .undocumented(let status, _): throw AppError.forStatus(status, serverMessage: nil)
        }
    }

    /// An assignment the server answered with, or a failure when its local times don't read.
    private static func assignment(_ a: Components.Schemas.Assignment) throws
        -> ReceiverWriteOutcome<AssignmentInfo> {
        guard let info = AssignmentInfo(a) else { throw AppError.unknown }
        return .done(info)
    }
}

// MARK: - Mapping from the generated types

extension CareReceiverInfo {
    init(_ d: Components.Schemas.CareReceiverDetail) {
        self.init(
            id: d.receiverId, teamID: d.teamId, teamName: d.teamName, name: d.name,
            timeZone: TimeZone(identifier: d.timeZone) ?? .current, isArchived: d.status == .archived,
            archivedByName: d.archivedByName, archivedAt: d.archivedAt,
            instructions: d.careInstructions.map {
                CareInstructionsInfo(body: $0.body, updatedByName: $0.updatedByName, updatedAt: $0.updatedAt)
            },
            contacts: d.emergencyContacts.map {
                EmergencyContactInfo(id: $0.contactId, name: $0.name, relationship: $0.relationship, phone: $0.phone)
            }
        )
    }
}

extension AssignmentInfo {
    /// Nil when its local times don't read as `YYYY-MM-DDTHH:MM` — nothing true can be
    /// said of it then.
    init?(_ a: Components.Schemas.Assignment) {
        guard let starts = LocalDateTime(a.startsLocal), let ends = LocalDateTime(a.endsLocal) else { return nil }
        self.init(id: a.assignmentId, receiverID: a.receiverId, userID: a.userId, caregiverName: a.caregiverName,
                  starts: starts, ends: ends, startsAt: a.startsAt, endsAt: a.endsAt,
                  coverageScheduleID: a.coverageScheduleId)
    }
}

extension CoverageScheduleInfo {
    init(_ c: Components.Schemas.CoverageSchedule) {
        self.init(id: c.coverageScheduleId, receiverID: c.receiverId, userID: c.userId,
                  caregiverName: c.caregiverName,
                  days: c.rule.byDay.compactMap { ScheduleWeekday(rawValue: $0.rawValue) }, interval: c.rule.interval,
                  startTime: c.startTime, endTime: c.endTime, startsOn: LocalDay(dayString: c.startsOn),
                  endsOn: c.endsOn.flatMap { LocalDay(dayString: $0) })
    }
}

extension AssignmentWrite {
    var schema: Components.Schemas.AssignmentWrite {
        .init(userId: userID, startsLocal: starts.string, endsLocal: ends.string)
    }
}

extension CoverageScheduleWrite {
    var schema: Components.Schemas.CoverageScheduleWrite {
        .init(userId: userID,
              rule: .init(freq: .weekly, interval: interval,
                          byDay: days.sorted().compactMap { Components.Schemas.Weekday(rawValue: $0.rawValue) }),
              startTime: startTime, endTime: endTime, endsOn: endsOn?.dayString)
    }
}
