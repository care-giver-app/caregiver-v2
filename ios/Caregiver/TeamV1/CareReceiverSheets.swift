import SwiftUI

/// A Care receiver sheet (Figma 451:3634 / 3655 / 3670 / 3735 / 3773): Cancel, the title
/// and Save in its bar, then its inputs. Save is the sheet's own; `onSave` decides whether
/// it goes.
private struct ReceiverFormSheet<Content: View>: View {
    let title: String
    let isSaving: Bool
    let canSave: Bool
    var detents: Set<PresentationDetent> = [.medium, .large]
    let onSave: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Colors.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TeamText.cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(TeamText.save, action: onSave)
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }
}

/// A box that opens a menu (Figma "Input" with the ⌃⌄ suffix).
private struct MenuBox: View {
    let text: String
    var muted = false

    var body: some View {
        HStack {
            Text(text)
                .foregroundStyle(muted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .contentShape(Rectangle())
    }
}

/// A sheet's problems and failure, under its inputs.
private struct SheetProblems: View {
    let problems: [String]
    let error: String?

    var body: some View {
        if let error {
            StrideAlertBanner(message: error).padding(.top, Theme.Spacing.md)
        }
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(problems, id: \.self) { p in
                    Text(p)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(.top, 12)
        }
    }
}

/// A wall-clock `HH:MM` as a Date the pickers read in UTC, so no zone is ever applied.
private enum Clock {
    static let utc = TimeZone(identifier: "UTC")!

    static func date(_ hhmm: String) -> Date {
        let minutes = LocalDateTime.minutes(hhmm) ?? 8 * 60
        return Date(timeIntervalSince1970: TimeInterval(minutes * 60))
    }

    static func time(_ date: Date) -> String {
        TrackerText.format(date, "HH:mm", utc)
    }

    static func binding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { date(get()) }, set: { set(time($0)) })
    }
}

/// A day picker for a day in the receiver's zone.
private func dayBinding(_ get: @escaping () -> LocalDay, _ set: @escaping (LocalDay) -> Void,
                        zone: TimeZone) -> Binding<Date> {
    Binding(get: { get().start(in: zone) }, set: { set(LocalDay($0, zone: zone)) })
}

/// The time pickers, side by side (Figma "Pair": Starts, Ends).
private struct HoursPair: View {
    let start: Binding<Date>
    let end: Binding<Date>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TeamLabeledInput(label: TeamText.starts) {
                DatePicker(TeamText.starts, selection: start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, Clock.utc)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TeamLabeledInput(label: TeamText.ends) {
                DatePicker(TeamText.ends, selection: end, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, Clock.utc)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Who an assignment or a coverage schedule names: the team's caregivers now.
private struct CaregiverMenu: View {
    let members: [TeamMemberInfo]
    let name: String?
    let membersFailed: Bool
    let choose: (String) -> Void

    var body: some View {
        TeamLabeledInput(label: TeamText.caregiver) {
            Menu {
                ForEach(members) { m in
                    Button(m.name) { choose(m.userID) }
                }
            } label: {
                MenuBox(text: name ?? TeamText.chooseCaregiver, muted: name == nil)
            }
        }
        if membersFailed {
            Text(TeamText.membersFailed)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.alert)
                .padding(.top, 6)
        }
    }
}

// MARK: - Edit care receiver

/// Edit care receiver (PRD; Figma 451:3634): name and time zone. `onSaved` hears the
/// receiver as saved, just before the sheet goes back to Care receiver.
struct EditCareReceiverSheet: View {
    @State private var model: EditCareReceiverModel
    let onSaved: (TeamReceiver) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: EditCareReceiverModel, onSaved: @escaping (TeamReceiver) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        ReceiverFormSheet(title: TeamText.editReceiverTitle, isSaving: model.isSaving, canSave: model.canSave,
                          detents: [.medium], onSave: save) {
            TeamLabeledInput(label: TeamText.name) {
                TextField("", text: $model.name)
                    .textContentType(.name)
                    .submitLabel(.done)
            }
            TeamLabeledInput(label: TeamText.timeZone) {
                Menu {
                    Picker(TeamText.timeZone, selection: $model.zone) {
                        ForEach(model.zones, id: \.identifier) { zone in
                            Text(AddCareReceiverModel.label(zone)).tag(zone)
                        }
                    }
                } label: {
                    MenuBox(text: AddCareReceiverModel.label(model.zone))
                }
            }
            .padding(.top, 16)
            SheetProblems(problems: [], error: model.error)
        }
    }

    private func save() {
        Task {
            if let saved = await model.save() {
                onSaved(saved)
                dismiss()
            }
        }
    }
}

// MARK: - Edit care instructions

/// Edit care instructions (PRD; Figma 451:3655): one free-form document, and who last
/// changed it. `onSaved` hears the receiver as saved.
struct EditInstructionsSheet: View {
    @State private var model: EditInstructionsModel
    let onSaved: (CareReceiverInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(model: EditInstructionsModel, onSaved: @escaping (CareReceiverInfo) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        ReceiverFormSheet(title: TeamText.instructionsTitle, isSaving: model.isSaving, canSave: model.canSave,
                          detents: [.large], onSave: save) {
            TextEditor(text: $model.body)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 380)
                .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
                .accessibilityLabel(TeamText.instructionsTitle)
            if let stamp = model.stamp {
                Text(TeamText.changedBy(stamp.updatedByName, at: stamp.updatedAt, now: Date(),
                                        zone: model.zone))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, 8)
            }
            SheetProblems(problems: model.isTooLong ? ["Keep the instructions to 20,000 characters or fewer."] : [],
                          error: model.error)
        }
        .onAppear { if model.body.isEmpty { focused = true } }
    }

    private func save() {
        Task {
            if let saved = await model.save() {
                onSaved(saved)
                dismiss()
            }
        }
    }
}

// MARK: - Emergency contacts

/// Emergency contacts (PRD; Figma 451:3670): each contact's name, relationship and phone,
/// with ≡ to drag it into place and × to remove it, then Add a contact. `onSaved` hears
/// the receiver as saved.
struct EmergencyContactsSheet: View {
    @State private var model: EmergencyContactsModel
    let onSaved: (CareReceiverInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: EmergencyContactsModel, onSaved: @escaping (CareReceiverInfo) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        ReceiverFormSheet(title: TeamText.contactsTitle, isSaving: model.isSaving, canSave: model.canSave,
                          detents: [.large], onSave: save) {
            ForEach($model.drafts) { $draft in
                contact($draft)
                    .padding(.bottom, 22)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
                        withAnimation { model.move(id, to: draft.id) }
                        return true
                    }
            }
            if model.canAdd {
                Button { withAnimation { model.add() } } label: { AddTrackerActionRow(title: TeamText.addContact) }
                    .buttonStyle(.plain)
            }
            if model.drafts.count > 1 {
                Text(TeamText.dragToReorder)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, 8)
            }
            SheetProblems(problems: model.problems, error: model.error)
        }
    }

    private func contact(_ draft: Binding<EmergencyContactsModel.Draft>) -> some View {
        let d = draft.wrappedValue
        let title = d.name.trimmingCharacters(in: .whitespaces).isEmpty ? TeamText.newContact : d.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("≡")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .draggable(d.id.uuidString) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .padding(10)
                            .background { RoundedRectangle(cornerRadius: 10).fill(Theme.Colors.surface) }
                    }
                    .accessibilityLabel("Reorder \(title)")
                    .accessibilityAction(named: "Move up") { model.move(d.id, by: -1) }
                    .accessibilityAction(named: "Move down") { model.move(d.id, by: 1) }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { withAnimation { model.remove(d.id) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.textOnAccent)
                        .frame(width: 22, height: 22)
                        .background { Circle().fill(Theme.Colors.alert) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
            }
            TeamLabeledInput(label: TeamText.name) {
                TextField("", text: draft.name).textContentType(.name)
            }
            HStack(alignment: .top, spacing: 12) {
                TeamLabeledInput(label: TeamText.relationship) {
                    TextField("", text: draft.relationship)
                }
                TeamLabeledInput(label: TeamText.phone) {
                    TextField("", text: draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            }
        }
    }

    private func save() {
        Task {
            if let saved = await model.save() {
                onSaved(saved)
                dismiss()
            }
        }
    }
}

// MARK: - An assignment

/// An assignment (PRD "An assignment"; Figma 451:3735): the caregiver, the day and the
/// hours. Saving someone else hands it to them; Remove drops this one alone. `onDone`
/// runs once either is written, just before the sheet goes back to Care receiver.
struct AssignmentSheet: View {
    @State private var model: AssignmentModel
    let membersFailed: Bool
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: AssignmentModel, membersFailed: Bool = false, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.membersFailed = membersFailed
        self.onDone = onDone
    }

    var body: some View {
        ReceiverFormSheet(title: TeamText.assignmentTitle, isSaving: model.isSaving, canSave: model.canSave,
                          onSave: { run { await model.save() } }) {
            CaregiverMenu(members: model.members, name: model.caregiverName, membersFailed: membersFailed) {
                model.userID = $0
            }
            TeamLabeledInput(label: TeamText.day) {
                DatePicker(TeamText.day, selection: dayBinding({ model.day }, { model.day = $0 }, zone: model.zone),
                           in: earliest..., displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.timeZone, model.zone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 16)
            HoursPair(start: Clock.binding(get: { model.startTime }, set: { model.setStart($0) }),
                      end: Clock.binding(get: { model.endTime }, set: { model.setEnd($0) }))
                .padding(.top, 16)
            if model.endDayOffset == 1 {
                caption("Ends the next day, at \(TrackerText.clock(model.endTime)).")
            }
            if model.existing?.coverageScheduleID != nil {
                caption(TeamText.fromRule(model.rule))
            }
            SheetProblems(problems: model.problems, error: model.error)
            if !model.isNew {
                StrideButton(title: TeamText.removeButton, style: .destructive, isLoading: model.isRemoving) {
                    run { await model.remove() }
                }
                .disabled(model.isSaving)
                .padding(.top, 20)
            }
        }
    }

    /// Today in the receiver's zone, or an earlier day an assignment under way began on.
    private var earliest: Date {
        let today = LocalDay(Date(), zone: model.zone)
        return min(today, model.existing?.starts.day ?? today).start(in: model.zone)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private func run(_ work: @escaping () async -> Bool) {
        Task {
            if await work() {
                onDone()
                dismiss()
            }
        }
    }
}

// MARK: - A coverage schedule

/// A coverage schedule (PRD "A coverage schedule"; Figma 451:3773): the caregiver, the
/// days, the hours, and when it ends. Remove asks first (Remove this coverage schedule?).
/// `onDone` runs once it is saved or removed, just before the sheet goes.
struct CoverageScheduleSheet: View {
    @State private var model: CoverageScheduleModel
    let membersFailed: Bool
    let onDone: () -> Void
    @State private var confirmingRemove = false
    /// Set by Remove this coverage schedule? once removed; read as that sheet goes.
    @State private var removed = false
    @Environment(\.dismiss) private var dismiss

    init(model: CoverageScheduleModel, membersFailed: Bool = false, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.membersFailed = membersFailed
        self.onDone = onDone
    }

    var body: some View {
        @Bindable var model = model
        ReceiverFormSheet(title: TeamText.coverageTitle, isSaving: model.isSaving, canSave: model.canSave,
                          detents: [.large], onSave: save) {
            CaregiverMenu(members: model.members, name: model.caregiverName, membersFailed: membersFailed) {
                model.userID = $0
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(TeamText.days)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                StrideWeekdayPicker(selected: model.days, size: 42) { model.toggle($0) }
            }
            .padding(.top, 16)
            HoursPair(start: Clock.binding(get: { model.startTime }, set: { model.startTime = $0 }),
                      end: Clock.binding(get: { model.endTime }, set: { model.endTime = $0 }))
                .padding(.top, 16)
            if let s = LocalDateTime.minutes(model.startTime), let e = LocalDateTime.minutes(model.endTime), e < s {
                Text("Runs past midnight, ending at \(TrackerText.clock(model.endTime)) the next day.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, 10)
            }
            TeamLabeledInput(label: TeamText.repeatsUntil) {
                Menu {
                    Button(TeamText.forever) { model.endsOn = nil }
                    Button(TeamText.onADate) { if model.endsOn == nil { model.endsOn = model.today } }
                } label: {
                    MenuBox(text: model.endsOn == nil ? TeamText.forever : TeamText.onADate)
                }
            }
            .padding(.top, 16)
            if model.endsOn != nil {
                DatePicker(TeamText.lastDay,
                           selection: dayBinding({ model.endsOn ?? model.today }, { model.endsOn = $0 },
                                                 zone: model.zone),
                           in: model.today.start(in: model.zone)..., displayedComponents: .date)
                    .environment(\.timeZone, model.zone)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.sm)
            }
            SheetProblems(problems: model.problems, error: model.error)
            if !model.isNew {
                StrideButton(title: TeamText.removeButton, style: .destructive) { confirmingRemove = true }
                    .disabled(model.isSaving)
                    .padding(.top, Theme.Spacing.lg)
            }
        }
        .sheet(isPresented: $confirmingRemove, onDismiss: {
            guard removed else { return }
            onDone()
            dismiss()
        }) {
            RemoveCoverageSheet(model: model) { removed = true }
        }
    }

    private func save() {
        Task {
            if await model.save() {
                onDone()
                dismiss()
            }
        }
    }
}

/// Remove this coverage schedule? (PRD; Figma 451:3825): what goes and what stays, then
/// Remove or Cancel. Cancel goes back to A coverage schedule; Remove to Care receiver.
struct RemoveCoverageSheet: View {
    let model: CoverageScheduleModel
    let onRemoved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TeamConfirmation(title: TeamText.removeCoverageTitle, line: TeamText.removeCoverageLine,
                         failure: model.removeError, isWorking: model.isRemoving) {
            TeamTile(icon: "calendar", size: 48)
        } buttons: {
            StrideButton(title: TeamText.removeButton, style: .destructive, isLoading: model.isRemoving) {
                Task {
                    if await model.remove() {
                        onRemoved()
                        dismiss()
                    }
                }
            }
            StrideButton(title: TeamText.cancel, style: .secondary) { dismiss() }
                .disabled(model.isRemoving)
        }
    }
}

// MARK: - Archive this care receiver?

/// Archive this care receiver? (PRD): what stops and what stays. Archive goes back to Care
/// receiver, now archived; `onArchived` runs first.
struct ArchiveReceiverSheet: View {
    @State private var model: ArchiveReceiverModel
    let onArchived: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: ArchiveReceiverModel, onArchived: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onArchived = onArchived
    }

    var body: some View {
        TeamConfirmation(title: TeamText.archiveTitle, line: TeamText.archiveLine(model.name),
                         failure: model.failure, isWorking: model.isWorking) {
            TeamMonogram(name: model.name, size: 48)
        } buttons: {
            StrideButton(title: TeamText.archiveButton, style: .destructive, isLoading: model.isWorking) {
                Task {
                    if await model.archive() {
                        onArchived()
                        dismiss()
                    }
                }
            }
            StrideButton(title: TeamText.cancel, style: .secondary) { dismiss() }
                .disabled(model.isWorking)
        }
    }
}

#if DEBUG
private enum ReceiverSheetPreview {
    static let eleanor = TeamFixtures.eleanorDetail
}

#Preview("Edit care receiver (451:3634)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditCareReceiverSheet(model: EditCareReceiverModel(info: ReceiverSheetPreview.eleanor,
                                                           service: TeamFixtures.service())) { _ in }
    }
}

#Preview("Edit care instructions (451:3655)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditInstructionsSheet(model: EditInstructionsModel(info: ReceiverSheetPreview.eleanor,
                                                           service: TeamFixtures.service())) { _ in }
    }
}

#Preview("Emergency contacts (451:3670)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        EmergencyContactsSheet(model: EmergencyContactsModel(info: ReceiverSheetPreview.eleanor,
                                                             service: TeamFixtures.service())) { _ in }
    }
}

#Preview("An assignment (451:3735)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AssignmentSheet(model: AssignmentModel(
            receiverID: HomeFixtures.eleanor.id, receiverName: "Eleanor", zone: HomeFixtures.eleanor.timeZone,
            existing: TeamFixtures.danaThursday, members: TeamFixtures.riversideDetail.members,
            rule: TeamFixtures.danaRule, service: TeamFixtures.service())) {}
    }
}

#Preview("A coverage schedule (451:3773)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CoverageScheduleSheet(model: CoverageScheduleModel(
            receiverID: HomeFixtures.eleanor.id, receiverName: "Eleanor", zone: HomeFixtures.eleanor.timeZone,
            existing: TeamFixtures.trevorRule, members: TeamFixtures.riversideDetail.members,
            service: TeamFixtures.service())) {}
    }
}

#Preview("Remove this coverage schedule? (451:3825)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RemoveCoverageSheet(model: CoverageScheduleModel(
            receiverID: HomeFixtures.eleanor.id, receiverName: "Eleanor", zone: HomeFixtures.eleanor.timeZone,
            existing: TeamFixtures.trevorRule, members: [], service: TeamFixtures.service())) {}
    }
}

#Preview("Archive this care receiver?") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ArchiveReceiverSheet(model: ArchiveReceiverModel(receiverID: HomeFixtures.eleanor.id, name: "Eleanor",
                                                         service: TeamFixtures.service())) {}
    }
}
#endif
