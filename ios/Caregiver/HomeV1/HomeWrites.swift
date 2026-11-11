import Foundation
import CaregiverAPI
import OpenAPIRuntime

/// Quick log's step for a picked tracker (`NewEntry`): care logged ad hoc, or — with `at`
/// in the future — a one-off scheduled entry planned by hand.
struct NewEntryWrite: Equatable, Sendable {
    /// Nil means now, as the server reads it.
    var at: Date?
    /// Keyed by field id. Logging must answer every required active field; planning
    /// pre-fills what can be known and may leave the rest out.
    var values: [String: EntryValue]
    var note: String?
    /// Only when `at` is in the future.
    var unrecordedAlert: Bool = false
}

/// What logging or editing an entry records (`EntryCare`).
struct EntryCareWrite: Equatable, Sendable {
    /// Never in the future: the run's one time when logging, the corrected time when editing.
    var occurredAt: Date
    var values: [String: EntryValue]
    var note: String?
}

/// A journal note's Save (`JournalNoteWrite`).
struct NoteWrite: Equatable, Sendable {
    /// The time it is about; never in the future.
    var at: Date
    var body: String
}

/// The server's 409 `EntryNotInState`: somebody settled the entry first, it is still
/// waiting, or its tracker is paused. Whoever sees it should reload and show what is
/// there now.
struct EntryNotInState: Error, Equatable {
    let message: String?
}

extension HomeService {
    /// This service with Quick log's waiting read and every Home write answered by `client`.
    func withWrites(_ client: Client) -> HomeService {
        var s = self
        s.waiting = { receiverID in
            switch try await client.listWaitingEntries(path: .init(receiverId: receiverID)) {
            case .ok(let ok): return try ok.body.json.map(ReceiverEntryItem.init)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.addEntry = { trackerID, write in
            let output = try await client.addEntry(path: .init(trackerId: trackerID),
                                                   body: .json(try write.generated))
            switch output {
            case .created(let created): return EntryDetailInfo(try created.body.json)
            case .badRequest(let bad): throw refusal(400, try? bad.body.json.message)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .conflict(let c): throw refusal(409, try? c.body.json.message)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.logEntry = { entryID, care in
            let output = try await client.logEntry(path: .init(entryId: entryID), body: .json(try care.generated))
            switch output {
            case .ok(let ok): return EntryDetailInfo(try ok.body.json)
            case .badRequest(let bad): throw refusal(400, try? bad.body.json.message)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .conflict(let c): throw refusal(409, try? c.body.json.message)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.skipEntry = { entryID, note in
            let output = try await client.skipEntry(path: .init(entryId: entryID),
                                                    body: .json(.init(note: note.nonBlank)))
            switch output {
            case .ok(let ok): return EntryDetailInfo(try ok.body.json)
            case .badRequest(let bad): throw refusal(400, try? bad.body.json.message)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .conflict(let c): throw refusal(409, try? c.body.json.message)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.changeEntry = { entryID, care in
            let output = try await client.changeEntry(path: .init(entryId: entryID), body: .json(try care.generated))
            switch output {
            case .ok(let ok): return EntryDetailInfo(try ok.body.json)
            case .badRequest(let bad): throw refusal(400, try? bad.body.json.message)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .conflict(let c): throw refusal(409, try? c.body.json.message)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.deleteEntry = { entryID in
            switch try await client.deleteEntry(path: .init(entryId: entryID)) {
            case .ok(let ok): return EntryDetailInfo(try ok.body.json)
            case .noContent: return nil
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .conflict(let c): throw refusal(409, try? c.body.json.message)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.addJournalNote = { receiverID, note in
            let output = try await client.addJournalNote(path: .init(receiverId: receiverID),
                                                         body: .json(note.generated))
            switch output {
            case .created(let created): return JournalNoteInfo(try created.body.json)
            case .badRequest(let bad): throw refusal(400, try? bad.body.json.message)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.changeJournalNote = { noteID, note in
            let output = try await client.changeJournalNote(path: .init(noteId: noteID), body: .json(note.generated))
            switch output {
            case .ok(let ok): return JournalNoteInfo(try ok.body.json)
            case .badRequest(let bad): throw refusal(400, try? bad.body.json.message)
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        s.deleteJournalNote = { noteID in
            switch try await client.deleteJournalNote(path: .init(noteId: noteID)) {
            case .noContent: return
            case .unauthorized: throw refusal(401)
            case .forbidden: throw refusal(403)
            case .notFound: throw refusal(404)
            case .undocumented(let status, _): throw refusal(status)
            }
        }
        return s
    }
}

/// The error for any answer but the one asked for, by status: a 409 is `EntryNotInState`,
/// anything else an `AppError` carrying the server's message when it gave one.
private func refusal(_ status: Int, _ message: String? = nil) -> Error {
    status == 409 ? EntryNotInState(message: message) : AppError.forStatus(status, serverMessage: message)
}

// MARK: - Mapping to the generated types

extension NewEntryWrite {
    var generated: Components.Schemas.NewEntry {
        get throws {
            .init(at: at, values: .init(additionalProperties: try EntryValue.object(values)),
                  note: note.nonBlank, unrecordedAlert: unrecordedAlert ? true : nil)
        }
    }
}

extension EntryCareWrite {
    var generated: Components.Schemas.EntryCare {
        get throws {
            .init(occurredAt: occurredAt, values: .init(additionalProperties: try EntryValue.object(values)),
                  note: note.nonBlank)
        }
    }
}

extension NoteWrite {
    var generated: Components.Schemas.JournalNoteWrite { .init(at: at, body: body) }
}

private extension Optional where Wrapped == String {
    /// A note with something in it, as the server keeps it; nil for blank.
    var nonBlank: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
