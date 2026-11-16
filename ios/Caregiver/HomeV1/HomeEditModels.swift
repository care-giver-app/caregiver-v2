import SwiftUI

/// Every sentence Edit entry, Edit journal note and the two delete confirmations say.
enum HomeEditText {
    static let editEntryTitle = "Edit entry"
    static let editNoteTitle = "Journal note"
    static let deleteEntryTitle = "Delete this entry?"
    static let deleteNoteTitle = "Delete this note?"

    /// Edit entry on a skipped entry: saving it logs the care (PRD "Entry detail").
    static let logsTheSkip = "This was skipped. Saving logs it instead: the care happened after all, "
        + "and you'll be who logged it."
    static let futureTime = "Choose a time that isn't in the future."
    static let noteRequired = "Write the note."
    static func noteTooLong(_ max: Int) -> String { "Keep the note to \(max) characters or fewer." }

    /// Delete this entry?, logged ad hoc (Figma 488:4159).
    static let adHocGone = "The entry will be gone, and this can’t be undone."

    /// Delete this entry?, having fulfilled a scheduled entry (Figma 445:4440). An entry
    /// planned by hand has no schedule to name.
    static func waitsAgain(schedule: String?) -> String {
        if let schedule, !schedule.isEmpty {
            return "It came from the \(schedule) schedule, so that time will be waiting to be logged again."
        }
        return "It was planned, so that time will be waiting to be logged again."
    }

    /// Delete this note? (PRD: "that the note will be gone").
    static let noteGone = "The note will be gone, and this can’t be undone."

    /// A 409: somebody moved the entry out of the state this write needed.
    static let changedFirst = "Someone changed this entry first, so nothing was saved. "
        + "Close this to see it as it is now."
    static let entryGoneSince = "This entry was deleted by someone else, so nothing was saved."
    static let noteGoneSince = "This note was deleted by someone else, so nothing was saved."
    static func couldNotSave(_ error: AppError) -> String { "Couldn't save. \(error.message)" }
    static func couldNotDelete(_ error: AppError) -> String { "Couldn't delete. \(error.message)" }
}

/// Why a write from one of these sheets did not land.
enum HomeEditFailure: Equatable {
    /// 409 `EntryNotInState`: it is no longer logged or skipped, or its tracker was paused.
    /// Entry detail reads itself again behind the sheet; this write cannot be retried.
    case notInState
    /// 404: deleted elsewhere. Also final.
    case gone
    /// Anything else; Save or Delete may be tried again.
    case other(AppError)

    /// Whether trying the same write again could help.
    var isFinal: Bool { self == .notInState || self == .gone }

    /// An edit that found its entry or note deleted elsewhere: as for a delete, Home is
    /// told and gone back to once the sheet is down, as there is nothing left to show.
    /// Anything else final reads the screen behind the sheet again.
    var sendsHome: Bool { self == .gone }

    static func from(_ error: Error) -> HomeEditFailure {
        if error is EntryNotInState { return .notInState }
        let e = AppError.from(error)
        return e.isNotFound ? .gone : .other(e)
    }
}

// MARK: - Edit entry

/// Edit entry (PRD "Edit entry"): one logged or skipped entry's fields as they were
/// logged, when it occurred, and its note. Times are in the receiver's zone and never in
/// the future. Editing a logged entry must keep answered every required field it already
/// answers; editing a skipped one logs it, so every required active field must be
/// answered, as for logging. Values held for fields paused or options retired since are
/// kept as they were.
@MainActor
@Observable
final class EditEntryModel {
    /// Save landed: the entry as it now stands, and the day it moved to in the receiver's
    /// zone when it is no longer on the day it was.
    struct Saved: Equatable {
        let detail: EntryDetailInfo
        let movedTo: LocalDay?
    }

    let original: EntryDetailInfo
    let zone: TimeZone
    var values: EntryValuesDraft
    /// When the care happened.
    var occurredAt: Date
    var note: String
    private(set) var isSaving = false
    private(set) var failure: HomeEditFailure?

    /// The fields the entry already answers, which an edit must keep answered.
    private let priorAnswered: Set<String>
    private let change: @Sendable (_ entryID: String, _ care: EntryCareWrite) async throws -> EntryDetailInfo
    private let clock: @MainActor () -> Date

    init(_ detail: EntryDetailInfo, zone: TimeZone, home: HomeService,
         clock: @escaping @MainActor () -> Date = { ServerClock.shared.now() }) {
        original = detail
        self.zone = zone
        change = home.changeEntry
        self.clock = clock
        let prior = detail.entry.values
        priorAnswered = Set(EntryValuesDraft(prior).sent(for: detail.fields, keeping: prior).keys)
        values = EntryValuesDraft(detail.entry.values)
        // A skip ahead of its time cannot be logged then: it starts at now instead.
        occurredAt = min(detail.entry.at, clock())
        note = detail.entry.note ?? ""
    }

    /// Editing a skipped entry logs the care after all; the caller becomes who logged it.
    var logsTheCare: Bool { original.entry.state == .skipped }

    /// The fields offered as inputs: a paused field takes no new value.
    var activeFields: [TrackerFieldInfo] { original.fields.filter { !$0.paused } }

    /// "Expected 90–140" under each value logged outside its range (Figma 445:4389).
    var hints: [String: String] {
        Dictionary(original.outOfRange.map { ($0.fieldID, HomeText.expectedUnderValue($0.range)) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// The latest time it may be set to.
    var latest: Date { clock() }

    var problems: [String] {
        let logs = logsTheCare
        let answered = priorAnswered
        var out = values.problems(for: original.fields, keeping: original.entry.values) { field in
            logs || answered.contains(field.id)
        }
        if occurredAt > clock() { out.append(HomeEditText.futureTime) }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).count > EntryValuesDraft.maxNote {
            out.append(HomeEditText.noteTooLong(EntryValuesDraft.maxNote))
        }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving && !(failure?.isFinal ?? false) }

    var failureLine: String? {
        switch failure {
        case nil: nil
        case .notInState: HomeEditText.changedFirst
        case .gone: HomeEditText.entryGoneSince
        case .other(let e): HomeEditText.couldNotSave(e)
        }
    }

    /// Sends the edit. Nil when it did not land; `failure` says why.
    func save() async -> Saved? {
        guard canSave else { return nil }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        let care = EntryCareWrite(occurredAt: occurredAt,
                                  values: values.sent(for: original.fields, keeping: original.entry.values),
                                  note: note)
        do {
            let saved = try await change(original.entry.id, care)
            let before = LocalDay(original.entry.at, zone: zone)
            let after = LocalDay(saved.entry.at, zone: zone)
            return Saved(detail: saved, movedTo: after == before ? nil : after)
        } catch {
            failure = .from(error)
            return nil
        }
    }
}

// MARK: - Delete this entry?

/// Delete this entry? (PRD "Delete this entry?"): says what deleting leaves behind —
/// an entry logged ad hoc is simply gone; one that fulfilled a scheduled entry leaves
/// that occurrence waiting again — then deletes it.
@MainActor
@Observable
final class DeleteEntryModel {
    enum Outcome: Equatable {
        /// It fulfilled a plan that still stands: the occurrence, waiting again, which Entry
        /// detail now shows as scheduled or unrecorded.
        case waitingAgain(EntryDetailInfo)
        /// Nothing is left to show (or it was deleted elsewhere first): back to Home.
        case gone
    }

    let detail: EntryDetailInfo
    private(set) var isDeleting = false
    private(set) var failure: HomeEditFailure?

    private let delete: @Sendable (_ entryID: String) async throws -> EntryDetailInfo?

    init(_ detail: EntryDetailInfo, home: HomeService) {
        self.detail = detail
        delete = home.deleteEntry
    }

    /// What deleting will leave behind.
    var explanation: String {
        detail.planned ? HomeEditText.waitsAgain(schedule: detail.entry.scheduleName) : HomeEditText.adHocGone
    }

    var canDelete: Bool { !isDeleting && failure != .notInState }

    var failureLine: String? {
        switch failure {
        case nil, .gone: nil
        case .notInState: HomeEditText.changedFirst
        case .other(let e): HomeEditText.couldNotDelete(e)
        }
    }

    /// Nil when it did not land. Deleted elsewhere first is `.gone` all the same.
    func confirm() async -> Outcome? {
        guard canDelete else { return nil }
        isDeleting = true
        failure = nil
        defer { isDeleting = false }
        do {
            return try await delete(detail.entry.id).map(Outcome.waitingAgain) ?? .gone
        } catch {
            let f = HomeEditFailure.from(error)
            if f == .gone { return .gone }
            failure = f
            return nil
        }
    }
}

// MARK: - Edit journal note

/// Edit journal note (PRD "Edit journal note"): the note and the time it is about, never
/// in the future, in the receiver's zone.
@MainActor
@Observable
final class EditJournalNoteModel {
    let original: JournalNoteInfo
    let zone: TimeZone
    var body: String
    var at: Date
    private(set) var isSaving = false
    private(set) var failure: HomeEditFailure?

    private let change: @Sendable (_ noteID: String, _ note: NoteWrite) async throws -> JournalNoteInfo
    private let clock: @MainActor () -> Date

    init(_ note: JournalNoteInfo, zone: TimeZone, home: HomeService,
         clock: @escaping @MainActor () -> Date = { ServerClock.shared.now() }) {
        original = note
        self.zone = zone
        change = home.changeJournalNote
        self.clock = clock
        body = note.body
        at = min(note.at, clock())
    }

    var latest: Date { clock() }

    var problems: [String] {
        var out: [String] = []
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { out.append(HomeEditText.noteRequired) }
        if trimmed.count > QuickLogModel.maxJournalNote {
            out.append(HomeEditText.noteTooLong(QuickLogModel.maxJournalNote))
        }
        if at > clock() { out.append(HomeEditText.futureTime) }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving && failure != .gone }

    var failureLine: String? {
        switch failure {
        case nil, .notInState: nil
        case .gone: HomeEditText.noteGoneSince
        case .other(let e): HomeEditText.couldNotSave(e)
        }
    }

    func save() async -> JournalNoteInfo? {
        guard canSave else { return nil }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            return try await change(original.id,
                                    NoteWrite(at: at, body: body.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            failure = .from(error)
            return nil
        }
    }
}

// MARK: - Delete this note?

/// Delete this note? (PRD "Delete this note?"): the note will be gone.
@MainActor
@Observable
final class DeleteJournalNoteModel {
    let note: JournalNoteInfo
    private(set) var isDeleting = false
    private(set) var failure: AppError?

    private let delete: @Sendable (_ noteID: String) async throws -> Void

    init(_ note: JournalNoteInfo, home: HomeService) {
        self.note = note
        delete = home.deleteJournalNote
    }

    var failureLine: String? { failure.map(HomeEditText.couldNotDelete) }

    /// Whether the note is gone — deleted here, or elsewhere first.
    func confirm() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        failure = nil
        defer { isDeleting = false }
        do {
            try await delete(note.id)
            return true
        } catch {
            let e = AppError.from(error)
            if e.isNotFound { return true }
            failure = e
            return false
        }
    }
}

// MARK: - Telling Home

/// One edit or delete on Entry detail or Journal note, for Home to reflect: whose it
/// was, and the day an edited entry now belongs to when it moved.
struct HomeWrite: Equatable, Sendable {
    let receiverID: String
    var movedTo: LocalDay? = nil
}

/// How many such writes there have been, and the last. Home and Tracker detail watch it
/// to read themselves again, as they watch `QuickLogRuns`.
struct HomeWriteLog: Equatable, Sendable {
    var count = 0
    var last: HomeWrite?

    mutating func record(_ write: HomeWrite) {
        count += 1
        last = write
    }
}

/// Reports a write to the tab shell, which counts it in `v1HomeWrites`. Elsewhere it does
/// nothing.
struct V1HomeWrote: Sendable {
    let report: @MainActor @Sendable (HomeWrite) -> Void

    @MainActor func callAsFunction(_ write: HomeWrite) { report(write) }
}

/// Takes the one `/v1` stack back to Home, its root — where deleting an ad hoc entry or a
/// journal note lands, as there is nothing left to show.
struct V1PopToHome: Sendable {
    let pop: @MainActor @Sendable () -> Void

    @MainActor func callAsFunction() { pop() }
}

private struct V1HomeWritesKey: EnvironmentKey {
    static let defaultValue = HomeWriteLog()
}

private struct V1HomeWroteKey: EnvironmentKey {
    static let defaultValue = V1HomeWrote { _ in }
}

private struct V1PopToHomeKey: EnvironmentKey {
    static let defaultValue = V1PopToHome {}
}

extension EnvironmentValues {
    var v1HomeWrites: HomeWriteLog {
        get { self[V1HomeWritesKey.self] }
        set { self[V1HomeWritesKey.self] = newValue }
    }

    var v1HomeWrote: V1HomeWrote {
        get { self[V1HomeWroteKey.self] }
        set { self[V1HomeWroteKey.self] = newValue }
    }

    var v1PopToHome: V1PopToHome {
        get { self[V1PopToHomeKey.self] }
        set { self[V1PopToHomeKey.self] = newValue }
    }
}
