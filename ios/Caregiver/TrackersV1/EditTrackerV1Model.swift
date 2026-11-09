import Foundation

/// Edit tracker (PRD "Edit tracker"): one tracker's name, icon, color, fields and gap,
/// committed together on Save and discarded on Cancel. Its schedules are listed here but
/// written by A schedule the moment that sheet saves. Pause tracker is offered from here.
@MainActor
@Observable
final class EditTrackerV1Model {
    /// The sheet's parts; the icon and color part swaps in place (PRD exits "as: stays").
    enum Part: Equatable {
        case tracker, iconColor
    }

    enum Schedules: Equatable {
        case loading
        case loaded([TrackerScheduleItem])
        case failed(AppError)
    }

    /// What Longest gap is typed in (Figma 373:3468 shows days). Stored as hours.
    enum GapUnit: String, CaseIterable, Equatable {
        case hours, days

        var hours: Int { self == .days ? 24 : 1 }
    }

    var part: Part = .tracker
    /// Name, icon, color and fields. The gap is held in `gapOn`/`gapAmount`/`gapUnit`
    /// and folded in by `write`.
    var draft: TrackerDraft
    private(set) var schedules: Schedules = .loading

    /// Alert after a gap.
    var gapOn: Bool
    /// Longest gap, as typed.
    var gapAmount: String
    var gapUnit: GapUnit

    private(set) var isSaving = false
    /// The last Save failed; the sheet stays, with the draft as it was.
    private(set) var saveFailed: AppError?
    /// Set when Save would turn the gap on over these schedules: the sheet asks before
    /// they go. Empty when the server refused and the schedules couldn't be read.
    var pendingRemoval: [TrackerScheduleItem]?

    private(set) var isPausing = false
    private(set) var pauseFailed: AppError?

    let profile: TrackerProfile
    let receiver: TeamReceiver
    private let service: TrackersService

    init(profile: TrackerProfile, receiver: TeamReceiver, service: TrackersService) {
        self.profile = profile
        self.receiver = receiver
        self.service = service
        self.draft = TrackerDraft(profile)
        if let hours = profile.gapHours {
            gapOn = true
            if hours % 24 == 0 {
                gapUnit = .days
                gapAmount = String(hours / 24)
            } else {
                gapUnit = .hours
                gapAmount = String(hours)
            }
        } else {
            gapOn = false
            gapUnit = .days
            gapAmount = ""
        }
    }

    // MARK: Who may do what

    /// Edit tracker is for admins only (PRD).
    var canEdit: Bool { receiver.canManage }
    /// Pause tracker is offered on an active tracker only; a paused one is resumed from
    /// Tracker detail.
    var canPause: Bool { receiver.canManage && profile.status == .active }

    // MARK: Schedules

    /// Read when the sheet opens. Task E's A schedule calls this again after it writes.
    func loadSchedules() async {
        do {
            schedules = .loaded(try await service.listSchedules(profile.id))
        } catch {
            schedules = .failed(AppError.from(error))
        }
    }

    var loadedSchedules: [TrackerScheduleItem] {
        if case .loaded(let s) = schedules { return s }
        return []
    }

    /// The schedules Save would remove: every one, once the gap is on.
    var schedulesLostToGap: [TrackerScheduleItem] {
        gapOn ? loadedSchedules : []
    }

    // MARK: Fields

    /// A field A field saved: replaces the one with its id, or adds it at the end.
    func save(_ field: FieldDraft) {
        if let i = draft.fields.firstIndex(where: { $0.id == field.id }) {
            draft.fields[i] = field
        } else {
            draft.fields.append(field)
        }
    }

    /// A field row's switch: on is collecting, off is paused. Never a delete.
    func setCollecting(_ id: FieldDraft.ID, _ collecting: Bool) {
        guard let i = draft.fields.firstIndex(where: { $0.id == id }) else { return }
        draft.fields[i].paused = !collecting
    }

    /// What Add a field opens A field on.
    func newField() -> FieldDraft {
        FieldDraft(label: "", kind: .text)
    }

    // MARK: Gap

    /// Longest gap in hours, or nil when off or not a whole number.
    var gapHours: Int? {
        guard gapOn, let n = Int(gapAmount.trimmingCharacters(in: .whitespaces)) else { return nil }
        return n * gapUnit.hours
    }

    // MARK: Save

    /// The draft with the gap folded in.
    private var current: TrackerDraft {
        var d = draft
        d.gapHours = gapOn ? (gapHours ?? 0) : nil
        return d
    }

    var problems: [String] {
        // The gap is checked here, from what was typed, rather than by the draft.
        var withoutGap = draft
        withoutGap.gapHours = nil
        var out = withoutGap.problems
        if gapOn {
            if gapHours == nil {
                out.append("Say how long the longest gap is.")
            } else if let h = gapHours, h < 1 {
                out.append("A gap must be at least 1 hour.")
            }
        }
        return out
    }

    var canSave: Bool { problems.isEmpty && !isSaving }

    var write: TrackerWrite { current.write }

    /// Save. Returns the tracker once saved. Nil when it can't be sent, failed, or the
    /// admin must first confirm losing schedules (`pendingRemoval` set).
    func save() async -> TrackerProfile? {
        guard canSave else { return nil }
        let losing = schedulesLostToGap
        if !losing.isEmpty {
            pendingRemoval = losing
            return nil
        }
        return await send(removeSchedules: false)
    }

    /// The admin confirmed the schedules may go.
    func confirmRemoval() async -> TrackerProfile? {
        guard canSave else { return nil }
        return await send(removeSchedules: true)
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    private func send(removeSchedules: Bool) async -> TrackerProfile? {
        isSaving = true
        saveFailed = nil
        defer { isSaving = false }
        do {
            let saved = try await service.editTracker(profile.id, write, removeSchedules)
            pendingRemoval = nil
            return saved
        } catch is SchedulesOrGapConflict where !removeSchedules {
            // Schedules this sheet didn't know about (or couldn't read): ask first.
            pendingRemoval = loadedSchedules
            return nil
        } catch {
            pendingRemoval = nil
            saveFailed = AppError.from(error)
            return nil
        }
    }

    // MARK: Pause

    /// Pause this tracker?'s Pause. True once paused; anything unsaved here is dropped.
    func pause() async -> Bool {
        guard canPause, !isPausing else { return false }
        isPausing = true
        pauseFailed = nil
        defer { isPausing = false }
        do {
            _ = try await service.pauseTracker(profile.id)
            return true
        } catch {
            pauseFailed = AppError.from(error)
            return false
        }
    }
}

/// How Edit tracker ended, for the screen that raised it.
enum EditTrackerOutcome: Equatable {
    /// Saved: the raiser reloads.
    case saved(TrackerProfile)
    /// Paused: the raiser goes back to Trackers.
    case paused
}
