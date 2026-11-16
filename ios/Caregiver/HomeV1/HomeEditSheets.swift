import SwiftUI

/// Edit entry (PRD "Edit entry"; Figma 445:4373): a sheet over Entry detail — Cancel,
/// the title and Save across the top, then the tracker's fields as they were logged, when
/// it occurred, and the note. Save hands back the entry as it now stands, then the sheet
/// goes; Cancel just goes. A write that cannot land — somebody changed the entry first,
/// or deleted it — is said in the sheet, and `onFailed` lets Entry detail read itself
/// again behind it.
struct EditEntrySheet: View {
    @State private var model: EditEntryModel
    let onSaved: (EditEntryModel.Saved) -> Void
    let onFailed: (HomeEditFailure) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: EditEntryModel, onSaved: @escaping (EditEntryModel.Saved) -> Void = { _ in },
         onFailed: @escaping (HomeEditFailure) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
        self.onFailed = onFailed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let line = model.failureLine {
                        StrideAlertBanner(message: line)
                    }
                    if model.logsTheCare {
                        Text(HomeEditText.logsTheSkip)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    EntryFieldInputs(fields: model.activeFields, values: $model.values, zone: model.zone,
                                     hints: model.hints)
                    HomeWhenInputs(date: $model.occurredAt, latest: model.latest, zone: model.zone)
                    QuickLogNoteInput(text: $model.note, minHeight: 110)
                    QuickLogProblems(problems: model.problems)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.surface)
            .navigationTitle(HomeEditText.editEntryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                HomeSheetToolbar(canSave: model.canSave, isSaving: model.isSaving, cancel: { dismiss() }) {
                    Task {
                        if let saved = await model.save() {
                            onSaved(saved)
                            dismiss()
                        } else if let failure = model.failure, failure.isFinal {
                            onFailed(failure)
                        }
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(model.isSaving)
    }
}

/// Edit journal note (PRD "Edit journal note"; Figma 447:4283): when it is about, then
/// the note. Save hands back the note as it now stands; Cancel goes.
struct EditJournalNoteSheet: View {
    @State private var model: EditJournalNoteModel
    let onSaved: (JournalNoteInfo) -> Void
    let onFailed: (HomeEditFailure) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: EditJournalNoteModel, onSaved: @escaping (JournalNoteInfo) -> Void = { _ in },
         onFailed: @escaping (HomeEditFailure) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
        self.onFailed = onFailed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let line = model.failureLine {
                        StrideAlertBanner(message: line)
                    }
                    HomeWhenInputs(date: $model.at, latest: model.latest, zone: model.zone)
                    QuickLogNoteInput(text: $model.body, minHeight: 180)
                    QuickLogProblems(problems: model.problems)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.surface)
            .navigationTitle(HomeEditText.editNoteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                HomeSheetToolbar(canSave: model.canSave, isSaving: model.isSaving, cancel: { dismiss() }) {
                    Task {
                        if let saved = await model.save() {
                            onSaved(saved)
                            dismiss()
                        } else if let failure = model.failure, failure.isFinal {
                            onFailed(failure)
                        }
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(model.isSaving)
    }
}

/// Cancel on the left, Save (semibold) on the right (Figma 445:4378).
private struct HomeSheetToolbar: ToolbarContent {
    let canSave: Bool
    let isSaving: Bool
    let cancel: () -> Void
    let save: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: cancel)
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }
}

/// Date and Time side by side (Figma 445:4395), in the receiver's zone and never later
/// than `latest`.
struct HomeWhenInputs: View {
    @Binding var date: Date
    let latest: Date
    let zone: TimeZone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            box("Date", components: .date)
            box("Time", components: .hourAndMinute)
        }
    }

    private func box(_ label: String, components: DatePicker.Components) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QuickLogFieldLabel(text: label)
            DatePicker(label, selection: $date, in: ...latest, displayedComponents: components)
                .labelsHidden()
                .environment(\.timeZone, zone)
                .quickLogInputBox()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The delete confirmations

/// Delete this entry? (PRD "Delete this entry?"; Figma 445:4410 ad hoc, 445:4428 from a
/// schedule): the tracker's tile, what deleting will leave behind, then Delete or Cancel.
/// `onDeleted` hears how it went before the sheet goes.
struct DeleteEntrySheet: View {
    @State private var model: DeleteEntryModel
    let onDeleted: (DeleteEntryModel.Outcome) -> Void
    let onFailed: (HomeEditFailure) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: DeleteEntryModel, onDeleted: @escaping (DeleteEntryModel.Outcome) -> Void = { _ in },
         onFailed: @escaping (HomeEditFailure) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onDeleted = onDeleted
        self.onFailed = onFailed
    }

    var body: some View {
        HomeDeleteConfirmation(title: HomeEditText.deleteEntryTitle, explanation: model.explanation,
                               failureLine: model.failureLine, isDeleting: model.isDeleting,
                               canDelete: model.canDelete) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: model.detail.tracker.color))
                .overlay {
                    Image(systemName: model.detail.tracker.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white)
                }
        } delete: {
            Task {
                if let outcome = await model.confirm() {
                    onDeleted(outcome)
                    dismiss()
                } else if let failure = model.failure, failure.isFinal {
                    onFailed(failure)
                }
            }
        }
    }
}

/// Delete this note? (PRD "Delete this note?"; Figma 447:4309): the note's tile, that it
/// will be gone, then Delete or Cancel.
struct DeleteJournalNoteSheet: View {
    @State private var model: DeleteJournalNoteModel
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: DeleteJournalNoteModel, onDeleted: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onDeleted = onDeleted
    }

    var body: some View {
        HomeDeleteConfirmation(title: HomeEditText.deleteNoteTitle, explanation: HomeEditText.noteGone,
                               failureLine: model.failureLine, isDeleting: model.isDeleting, canDelete: true) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.violetTint)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.Colors.trackerViolet)
                }
        } delete: {
            Task {
                if await model.confirm() {
                    onDeleted()
                    dismiss()
                }
            }
        }
    }
}

/// A delete confirmation's face (Figma 445:4414): a 48pt tile, the question, what
/// deleting leaves behind, then Delete (red) over Cancel.
private struct HomeDeleteConfirmation<Tile: View>: View {
    let title: String
    let explanation: String
    let failureLine: String?
    let isDeleting: Bool
    let canDelete: Bool
    @ViewBuilder let tile: Tile
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tile
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
            Text(explanation)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let failureLine {
                StrideAlertBanner(message: failureLine)
                    .padding(.top, Theme.Spacing.md)
            }
            VStack(spacing: 10) {
                StrideButton(title: "Delete", style: .destructive, isLoading: isDeleting) {
                    guard canDelete, !isDeleting else { return }
                    delete()
                }
                .disabled(!canDelete)
                .opacity(canDelete || isDeleting ? 1 : 0.5)
                StrideButton(title: "Cancel", style: .secondary) { dismiss() }
                    .disabled(isDeleting)
            }
            .padding(.top, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDeleting)
        .tint(Theme.Colors.accent)
    }
}

#if DEBUG
private enum HomeEditPreview {
    @MainActor static func edit(_ detail: EntryDetailInfo) -> some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            EditEntrySheet(model: EditEntryModel(detail, zone: HomeFixtures.chicago, home: HomeFixtures.service()))
        }
    }

    @MainActor static func delete(_ detail: EntryDetailInfo) -> some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            DeleteEntrySheet(model: DeleteEntryModel(detail, home: HomeFixtures.service()))
        }
    }
}

#Preview("Edit entry (445:4373)") {
    HomeEditPreview.edit(HomeFixtures.loggedOutOfRangeDetail)
}

#Preview("Edit entry, skipped") {
    HomeEditPreview.edit(HomeFixtures.skippedDetail)
}

#Preview("Delete this entry? · ad hoc (445:4410)") {
    HomeEditPreview.delete(HomeFixtures.loggedOutOfRangeDetail)
}

#Preview("Delete this entry? · from a schedule (445:4428)") {
    HomeEditPreview.delete(HomeFixtures.loggedFromScheduleDetail)
}

#Preview("Edit journal note (447:4283)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditJournalNoteSheet(model: EditJournalNoteModel(HomeFixtures.afternoonNote, zone: HomeFixtures.chicago,
                                                         home: HomeFixtures.service()))
    }
}

#Preview("Delete this note? (447:4309)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DeleteJournalNoteSheet(model: DeleteJournalNoteModel(HomeFixtures.afternoonNote,
                                                             home: HomeFixtures.service()))
    }
}
#endif
