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

    /// The gap as the server has it: the tracker's saved gap, until a first schedule
    /// replaces it. Unsaved changes to `gapOn` don't move it.
    private(set) var savedGapHours: Int?
    /// A schedule was added, changed or removed while this sheet was open. Those write at
    /// once, so the raiser reloads even if Edit tracker is cancelled.
    private(set) var schedulesChanged = false

    /// The tracker as last saved: as opened, or as a save made to open a schedule left it.
    private(set) var profile: TrackerProfile
    /// What `write` was right after the last save (or on open); anything else is unsaved.
    private var baseline: TrackerWrite!
    let receiver: TeamReceiver
    let service: TrackersService

    init(profile: TrackerProfile, receiver: TeamReceiver, service: TrackersService) {
        self.profile = profile
        self.receiver = receiver
        self.service = service
        self.draft = TrackerDraft(profile)
        self.savedGapHours = profile.gapHours
        (gapOn, gapUnit, gapAmount) = Self.gapState(profile.gapHours)
        baseline = write
    }

    private static func gapState(_ gapHours: Int?) -> (Bool, GapUnit, String) {
        if let hours = gapHours {
            return hours % 24 == 0 ? (true, .days, String(hours / 24)) : (true, .hours, String(hours))
        }
        return (false, .days, "")
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

    /// A schedule saved or was removed (written already): catch up, and read the list
    /// again. Only a save that replaced the tracker's saved gap turns the gap off here.
    func scheduleWritten(_ outcome: ScheduleSheetModel.Outcome) async {
        schedulesChanged = true
        if case .saved(_, replacedGap: true) = outcome {
            savedGapHours = nil
            gapOn = false
        }
        await loadSchedules()
    }

    /// A new schedule would replace the saved gap: the tracker has one and no schedules.
    var newScheduleReplacesGap: Bool {
        savedGapHours != nil && loadedSchedules.isEmpty
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

    /// A field row's switch: on is collecting, off is paused. Never a delete.
    func setCollecting(_ id: FieldDraft.ID, _ collecting: Bool) {
        guard let i = draft.fields.firstIndex(where: { $0.id == id }) else { return }
        draft.fields[i].paused = !collecting
    }


    // MARK: Gap

    /// The longest gap Save accepts: a year. Anything longer reads as a typo, and a
    /// bigger number could overflow on the way to hours.
    static let maxGapHours = 365 * 24

    /// Longest gap in hours, or nil when off or not a whole number. Never overflows: a
    /// number too big to convert comes back as `Int.max`, which `problems` refuses.
    var gapHours: Int? {
        guard gapOn, let n = Int(gapAmount.trimmingCharacters(in: .whitespaces)) else { return nil }
        let (hours, overflow) = n.multipliedReportingOverflow(by: gapUnit.hours)
        if overflow { return n < 0 ? Int.min : Int.max }
        return hours
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
            } else if let h = gapHours, h > Self.maxGapHours {
                out.append("A gap can be at most 365 days.")
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

    // MARK: Saving before a schedule

    /// Something here differs from the tracker as last saved.
    var hasUnsavedChanges: Bool { write != baseline }

    /// Saves what's here and keeps the sheet open, so a schedule opened next can pre-fill
    /// a field added in this session (PRD "Edit tracker"). Returns the saved tracker; nil
    /// when it can't be sent, failed, or the admin must first confirm losing schedules
    /// (`pendingRemoval` set) — then `saveBeforeSchedule(removeSchedules: true)` finishes it.
    func saveBeforeSchedule(removeSchedules: Bool = false) async -> TrackerProfile? {
        guard canSave else { return nil }
        if !removeSchedules {
            let losing = schedulesLostToGap
            if !losing.isEmpty {
                pendingRemoval = losing
                return nil
            }
        }
        guard let saved = await send(removeSchedules: removeSchedules) else { return nil }
        adopt(saved)
        if removeSchedules { await loadSchedules() }
        return saved
    }

    /// Starts again from the saved tracker: new fields now carry their ids, and Cancel
    /// from here discards only what changes after this.
    private func adopt(_ saved: TrackerProfile) {
        profile = saved
        let part = self.part
        draft = TrackerDraft(saved)
        self.part = part
        savedGapHours = saved.gapHours
        (gapOn, gapUnit, gapAmount) = Self.gapState(saved.gapHours)
        baseline = write
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
    /// Not saved, but a schedule was written meanwhile: the raiser reloads.
    case schedulesChanged
}
