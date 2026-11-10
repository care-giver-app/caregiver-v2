import SwiftUI

/// Edit tracker (PRD "Edit tracker"; Figma 373:3398 with schedules, 373:3468 with a gap):
/// a sheet over Tracker detail or Schedules, admins only. Name, icon, color, fields and
/// gap commit on Save; Cancel discards them. The icon and color part swaps in place.
/// `onFinished` hears how it ended, before the sheet goes: the raiser reloads on
/// `.saved` or `.schedulesChanged` and goes back to Trackers on `.paused`, in the sheet's
/// `onDismiss`. `.schedulesChanged` is heard as each schedule writes; a later Save or
/// Pause replaces it.
struct EditTrackerV1Sheet: View {
    /// Which of A schedule's two entries was taken: Add a schedule, or a schedule's row.
    enum ScheduleTarget: Identifiable, Equatable {
        case new
        case existing(TrackerScheduleItem)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let s): s.id
            }
        }
    }

    /// A schedule's sheet item, holding the model it was opened with.
    struct OpenedSchedule: Identifiable {
        let id = UUID()
        let model: ScheduleSheetModel
    }

    private let trackerID: String
    private let receiver: TeamReceiver
    private let service: TrackersService
    private let onFinished: (EditTrackerOutcome) -> Void

    @State private var model: EditTrackerV1Model?
    @State private var loadFailed: AppError?
    /// The field A field is open on.
    @State private var editingField: FieldDraft?
    @State private var confirmingPause = false
    /// A schedule, while open: its model is built once, when it opens.
    @State private var openedSchedule: OpenedSchedule?
    /// A schedule asked for while something here is unsaved: it opens once that is saved.
    @State private var scheduleAfterSave: ScheduleTarget?
    @State private var askingToSaveFirst = false
    /// Set by Pause this tracker? once the tracker is paused; read as that sheet goes.
    @State private var paused = false
    @Environment(\.dismiss) private var dismiss

    /// From Tracker detail, which already has the tracker.
    init(profile: TrackerProfile, receiver: TeamReceiver, service: TrackersService,
         onFinished: @escaping (EditTrackerOutcome) -> Void) {
        trackerID = profile.id
        self.receiver = receiver
        self.service = service
        self.onFinished = onFinished
        _model = State(initialValue: EditTrackerV1Model(profile: profile, receiver: receiver, service: service))
    }

    /// From Schedules, which only knows the tracker's id: the sheet reads it first.
    init(trackerID: String, receiver: TeamReceiver, service: TrackersService,
         onFinished: @escaping (EditTrackerOutcome) -> Void) {
        self.trackerID = trackerID
        self.receiver = receiver
        self.service = service
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    switch model.part {
                    case .tracker: tracker(model)
                    case .iconColor:
                        TrackerIconColorPart(icon: Bindable(model).draft.icon, color: Bindable(model).draft.color,
                                             name: model.draft.name) { model.part = .tracker }
                    }
                } else if loadFailed != nil {
                    StrideErrorState(message: "Couldn't load this tracker.") {
                        Task { await loadProfile() }
                    }
                    .toolbar { cancelItem }
                } else {
                    StrideLoadingView()
                        .toolbar { cancelItem }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Edit tracker")
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(model?.isSaving ?? false)
        .task {
            if model == nil { await loadProfile() }
            await model?.loadSchedules()
        }
    }

    private func loadProfile() async {
        loadFailed = nil
        do {
            let profile = try await service.trackerDetail(trackerID)
            model = EditTrackerV1Model(profile: profile, receiver: receiver, service: service)
        } catch {
            loadFailed = AppError.from(error)
        }
    }

    private var cancelItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: The tracker

    private func tracker(_ model: EditTrackerV1Model) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let failed = model.saveFailed {
                    StrideAlertBanner(message: "Couldn't save the tracker. \(failed.message)")
                        .padding(.bottom, Theme.Spacing.md)
                }
                HStack(spacing: 12) {
                    Button { model.part = .iconColor } label: {
                        TrackerIconPreview(icon: model.draft.icon, color: model.draft.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Icon and color")
                    StrideField(placeholder: "Name", text: $model.draft.name)
                }

                TrackerSectionLabel("FIELDS").padding(.top, 20).padding(.bottom, Theme.Spacing.sm)
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(model.draft.fields) { field in
                        fieldRow(field, model: model)
                    }
                    Button { editingField = FieldDraft.blank() } label: {
                        AddTrackerActionRow(title: "Add a field")
                    }
                    .buttonStyle(.plain)
                }

                gap(model)

                TrackerSectionLabel("SCHEDULES").padding(.top, 20).padding(.bottom, Theme.Spacing.sm)
                schedules(model)

                if !model.problems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.problems, id: \.self) { Text($0) }
                    }
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Spacing.md)
                }

                // Only on an active tracker: a paused one is resumed from Tracker detail.
                if model.canPause {
                    StrideButton(title: "Pause tracker", style: .secondary) { confirmingPause = true }
                        .disabled(model.isSaving)
                        .padding(.top, Theme.Spacing.lg)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .alert(model.canSave ? "Save your changes first?" : "Finish your changes first",
               isPresented: $askingToSaveFirst) {
            if model.canSave {
                Button("Save and continue") {
                    if let target = scheduleAfterSave { Task { await saveThenOpen(target, model) } }
                }
                Button("Cancel", role: .cancel) { scheduleAfterSave = nil }
            } else {
                Button("OK", role: .cancel) { scheduleAfterSave = nil }
            }
        } message: {
            if model.canSave {
                Text("A schedule can only pre-fill fields the tracker already has, so your changes are saved before it opens.")
            } else {
                Text(model.problems.joined(separator: "\n"))
            }
        }
        .background(Theme.Colors.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(model.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await finish(await model.save()) } }
                        .fontWeight(.semibold)
                        .disabled(!model.canSave)
                }
            }
        }
        .sheet(item: $editingField) { field in
            // No Remove: a field on a tracker that exists is paused from its switch instead.
            FieldSheet(field: field, onSave: { model.draft.upsert($0) })
        }
        .sheet(item: $openedSchedule) { opened in
            ScheduleSheet(model: opened.model) { outcome in
                // Written already, so Edit tracker only catches up, and the raiser will
                // reload however this sheet ends.
                onFinished(.schedulesChanged)
                Task { await model.scheduleWritten(outcome) }
            }
        }
        .sheet(isPresented: $confirmingPause, onDismiss: {
            guard paused else { return }
            onFinished(.paused)
            dismiss()
        }) {
            PauseTrackerV1Sheet(model: model) { paused = true }
        }
        .alert(removalTitle(model), isPresented: removalShown(model)) {
            Button("Remove and save", role: .destructive) {
                if let target = scheduleAfterSave {
                    Task { await saveThenOpen(target, model, removeSchedules: true) }
                } else {
                    Task { await finish(await model.confirmRemoval()) }
                }
            }
            Button("Cancel", role: .cancel) {
                scheduleAfterSave = nil
                model.cancelRemoval()
            }
        } message: {
            Text(removalMessage(model))
        }
    }

    private func finish(_ saved: TrackerProfile?) async {
        guard let saved else { return }
        onFinished(.saved(saved))
        dismiss()
    }

    /// Figma `Stride/Field Row` Mode=Toggle (415:3218): a paused field reads faded.
    private func fieldRow(_ field: FieldDraft, model: EditTrackerV1Model) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label.isEmpty ? "Unnamed field" : field.label)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(field.paused ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                Text(field.rowSummary)
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            Toggle(isOn: Binding(get: { !field.paused }, set: { model.setCollecting(field.id, $0) })) {
                EmptyView()
            }
            .toggleStyle(.stride)
            .fixedSize()
            .accessibilityLabel(field.paused ? "\(field.label), paused" : "\(field.label), collecting")
            Button { editingField = field } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 24, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change \(field.label)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { editingField = field }
        .modifier(AddTrackerCard())
    }

    // MARK: Gap

    @ViewBuilder
    private func gap(_ model: EditTrackerV1Model) -> some View {
        @Bindable var model = model
        TrackerSectionLabel("GAP").padding(.top, 20).padding(.bottom, Theme.Spacing.sm)
        Toggle("Alert after a gap", isOn: $model.gapOn)
            .toggleStyle(.stride)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 56)
            .modifier(AddTrackerCard())
        if model.gapOn {
            Text("Longest gap")
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 6)
            HStack {
                TextField("", text: $model.gapAmount)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Longest gap")
                Menu {
                    Picker("Unit", selection: $model.gapUnit) {
                        ForEach(EditTrackerV1Model.GapUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(model.gapUnit.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 52)
            .modifier(AddTrackerCard())
            if let hours = model.gapHours, hours >= 1, hours <= EditTrackerV1Model.maxGapHours {
                caption("If nothing is logged for \(TrackerText.duration(hours: hours)), the team is alerted.")
            }
            if !model.schedulesLostToGap.isEmpty {
                caption("Saving with the gap on removes this tracker's schedules. A tracker has one or the other.")
                    .foregroundStyle(Theme.Colors.alert)
            }
        }
    }

    // MARK: Schedules

    @ViewBuilder
    private func schedules(_ model: EditTrackerV1Model) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            switch model.schedules {
            case .loading:
                ProgressView()
                    .tint(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
            case .failed:
                StrideAlertBanner(message: "Couldn't load the schedules.")
                StrideButton(title: "Try again", style: .compact) {
                    Task { await model.loadSchedules() }
                }
            case .loaded(let schedules):
                ForEach(schedules) { schedule in
                    Button { openSchedule(.existing(schedule), model) } label: { scheduleRow(schedule) }
                        .buttonStyle(.plain)
                }
                Button { openSchedule(.new, model) } label: {
                    AddTrackerActionRow(title: "Add a schedule")
                }
                .buttonStyle(.plain)
            }
        }
        if model.newScheduleReplacesGap {
            caption("Adding a schedule turns off the gap. A tracker has one or the other.")
        }
    }

    /// A schedule, over this sheet; it writes on its own Save or Remove. With something
    /// here unsaved it asks to save that first, because a schedule can only pre-fill
    /// fields the tracker already has (PRD "Edit tracker").
    private func openSchedule(_ target: ScheduleTarget, _ model: EditTrackerV1Model) {
        if model.hasUnsavedChanges {
            scheduleAfterSave = target
            askingToSaveFirst = true
        } else {
            openedSchedule = OpenedSchedule(model: ScheduleSheetModel(editing: model, target: target))
        }
    }

    private func saveThenOpen(_ target: ScheduleTarget, _ model: EditTrackerV1Model,
                              removeSchedules: Bool = false) async {
        guard let saved = await model.saveBeforeSchedule(removeSchedules: removeSchedules) else {
            // Waiting on "Remove N schedules?" keeps the target; a refusal or failure drops it.
            if model.pendingRemoval == nil { scheduleAfterSave = nil }
            return
        }
        scheduleAfterSave = nil
        // Saved now, so the raiser reloads however this sheet ends.
        onFinished(.saved(saved))
        // A schedule the save just removed (gap turned on) is gone; there is nothing to open.
        if case .existing(let s) = target, !model.loadedSchedules.contains(where: { $0.id == s.id }) { return }
        openSchedule(target, model)
    }

    private func scheduleRow(_ schedule: TrackerScheduleItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(TrackerText.scheduleLine(schedule))
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .modifier(AddTrackerCard())
    }

    // MARK: Schedules or a gap

    private func removalShown(_ model: EditTrackerV1Model) -> Binding<Bool> {
        Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })
    }

    private func removalTitle(_ model: EditTrackerV1Model) -> String {
        let n = model.pendingRemoval?.count ?? 0
        return n == 1 ? "Remove 1 schedule?" : n > 1 ? "Remove \(n) schedules?" : "Remove its schedules?"
    }

    private func removalMessage(_ model: EditTrackerV1Model) -> String {
        let names = (model.pendingRemoval ?? []).map(\.name)
        let what = names.isEmpty
            ? "every schedule on this tracker"
            : ListFormatter.localizedString(byJoining: names)
        return "A tracker has schedules or a gap, never both. Saving with the gap on removes \(what), "
            + "and every occurrence still waiting. Everything already logged stays."
    }

    // MARK: Pieces

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

/// Pause this tracker? (PRD; Figma 373:3520): what stops and what is kept, then Pause or
/// Cancel. `onPaused` runs once the tracker is paused, just before this sheet goes.
struct PauseTrackerV1Sheet: View {
    let model: EditTrackerV1Model
    let onPaused: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// What stops, then what is kept (PRD "Pause this tracker?").
    static let explanation = "Nothing new can be logged, its schedules stop, and its thresholds stop alerting. "
        + "It leaves Home and the logging picker, and the occurrences already waiting go. "
        + "Every entry ever logged stays, in the timelines it appeared in and the insights it fed."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TrackerIconTile(icon: model.profile.icon, color: model.profile.color, size: 40)
                    .accessibilityHidden(true)
                Text("Pause \(model.profile.name)?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(Self.explanation)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.md)
            if let failed = model.pauseFailed {
                StrideAlertBanner(message: "Couldn't pause the tracker. \(failed.message)")
                    .padding(.top, Theme.Spacing.md)
            }
            VStack(spacing: 12) {
                StrideButton(title: "Pause tracker", isLoading: model.isPausing) {
                    Task {
                        if await model.pause() {
                            onPaused()
                            dismiss()
                        }
                    }
                }
                StrideButton(title: "Cancel", style: .secondary) { dismiss() }
                    .disabled(model.isPausing)
            }
            .padding(.top, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isPausing)
        .tint(Theme.Colors.accent)
    }
}

#if DEBUG
#Preview("With schedules") {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditTrackerV1Sheet(profile: TrackersFixtures.medication, receiver: TrackersFixtures.eleanor,
                           service: TrackersFixtures.service()) { _ in }
    }
}

#Preview("With a gap") {
    var service = TrackersFixtures.service()
    service.listSchedules = { _ in [] }
    return Color.clear.sheet(isPresented: .constant(true)) {
        EditTrackerV1Sheet(profile: TrackersFixtures.weight, receiver: TrackersFixtures.eleanor,
                           service: service) { _ in }
    }
}

#Preview("Paused tracker") {
    var service = TrackersFixtures.service()
    service.listSchedules = { _ in [] }
    return Color.clear.sheet(isPresented: .constant(true)) {
        EditTrackerV1Sheet(profile: TrackersFixtures.walk, receiver: TrackersFixtures.eleanor,
                           service: service) { _ in }
    }
}

#Preview("Pause this tracker?") {
    Color.clear.sheet(isPresented: .constant(true)) {
        PauseTrackerV1Sheet(model: EditTrackerV1Model(profile: TrackersFixtures.walk.with(status: .active),
                                                      receiver: TrackersFixtures.eleanor,
                                                      service: TrackersFixtures.service())) {}
    }
}
#endif
