import SwiftUI

/// A schedule (PRD "A schedule"; Figma 375:3532 existing, 375:3600 new on a gap tracker):
/// a sheet over Edit tracker. Save writes at once — `addSchedule` for a new one,
/// `changeSchedule` for an existing one — and Remove raises Remove this schedule?.
/// `onFinished` hears how it ended, just before the sheet goes.
struct ScheduleSheet: View {
    @State private var model: ScheduleSheetModel
    private let onFinished: (ScheduleSheetModel.Outcome) -> Void

    @State private var confirmingRemove = false
    /// Set by Remove this schedule? once removed; read as that sheet goes.
    @State private var removed = false
    @Environment(\.dismiss) private var dismiss

    init(model: ScheduleSheetModel, onFinished: @escaping (ScheduleSheetModel.Outcome) -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    /// Figma's week runs Sunday first.
    private static let week: [ScheduleWeekday] = [.su, .mo, .tu, .we, .th, .fr, .sa]
    private static let dayLetters: [ScheduleWeekday: String] = [.su: "S", .mo: "M", .tu: "T", .we: "W",
                                                                 .th: "T", .fr: "F", .sa: "S"]
    private static let dayNames: [ScheduleWeekday: String] = [.su: "Sunday", .mo: "Monday", .tu: "Tuesday",
                                                               .we: "Wednesday", .th: "Thursday",
                                                               .fr: "Friday", .sa: "Saturday"]
    static let blank = "Left for whoever logs it"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let failed = model.saveFailed {
                        StrideAlertBanner(message: "Couldn't save the schedule. \(failed.message)")
                            .padding(.bottom, Theme.Spacing.md)
                    }
                    if model.replacesGap { gapCallout }
                    name
                    days
                    repeatsAndTime
                    ends
                    prefilled
                    alert
                    problems
                    if !model.isNew {
                        StrideButton(title: "Remove", style: .destructive) { confirmingRemove = true }
                            .disabled(model.isSaving)
                            .padding(.top, Theme.Spacing.lg)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.surface)
            .navigationTitle(model.isNew ? "New schedule" : "Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { finish(await model.save()) } }
                            .fontWeight(.semibold)
                            .disabled(!model.canSave)
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(model.isSaving || model.isRemoving)
        .alert("Turn off the gap?", isPresented: $model.confirmingGap) {
            Button("Save and turn it off") { Task { finish(await model.confirmReplaceGap()) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.trackerName) alerts after a gap. A tracker has schedules or a gap, never both, "
                 + "so saving this schedule turns the gap off.")
        }
        .sheet(isPresented: $confirmingRemove, onDismiss: {
            guard removed else { return }
            onFinished(.removed)
            dismiss()
        }) {
            RemoveScheduleV1Sheet(model: model) { removed = true }
        }
    }

    private func finish(_ outcome: ScheduleSheetModel.Outcome?) {
        guard let outcome else { return }
        onFinished(outcome)
        dismiss()
    }

    // MARK: Parts

    /// Figma 375:3600: the first schedule on a gap-watched tracker says the gap goes.
    private var gapCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            TrackerIconTile(icon: "exclamationmark.circle", color: model.trackerColor, size: 32)
            Text(gapSentence)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.accentTint) }
        .padding(.bottom, Theme.Spacing.md)
    }

    private var gapSentence: String {
        let gap: String
        if let hours = model.gapHours, hours >= 1 {
            gap = hours >= 24 && hours % 24 == 0 ? "a \(hours / 24)-day gap" : "a \(hours)-hour gap"
        } else {
            gap = "a gap"
        }
        return "\(model.trackerName) alerts after \(gap). Saving a schedule turns that off."
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Name")
            StrideField(placeholder: model.derivedName ?? "Such as Morning", text: $model.draft.label)
            if let derived = model.derivedName {
                caption("Leave blank to call it “\(derived)”.")
            } else {
                caption("Leave blank to name it after when it repeats.")
            }
        }
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Days").padding(.top, Theme.Spacing.md)
            HStack(spacing: 0) {
                ForEach(Array(Self.week.enumerated()), id: \.offset) { i, day in
                    if i > 0 { Spacer(minLength: 4) }
                    dayButton(day)
                }
            }
        }
    }

    private func dayButton(_ day: ScheduleWeekday) -> some View {
        let on = model.draft.days.contains(day)
        return Button { model.toggle(day) } label: {
            Text(Self.dayLetters[day] ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.Colors.textSecondary)
                .frame(width: 40, height: 40)
                .background { Circle().fill(on ? Theme.Colors.accent : Theme.Colors.surface) }
                .overlay { Circle().stroke(on ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.dayNames[day] ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var repeatsAndTime: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                heading("Repeats")
                Menu {
                    Picker("Repeats", selection: $model.draft.interval) {
                        ForEach(ScheduleDraft.intervals, id: \.self) { n in
                            Text(TrackerText.repeats(intervalWeeks: n)).tag(n)
                        }
                    }
                } label: {
                    menuBox(TrackerText.repeats(intervalWeeks: model.draft.interval))
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                heading("Time")
                // The time is the receiver's wall clock, stored as HH:MM: the picker reads
                // and writes it in UTC so no zone is applied either way.
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, Self.utc)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 46)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, Theme.Spacing.md)
    }

    private var ends: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Ends").padding(.top, Theme.Spacing.md)
            Menu {
                Button("Never") { model.draft.endsOn = nil }
                Button("On a date") {
                    if model.draft.endsOn == nil { model.draft.endsOn = model.today }
                }
            } label: {
                menuBox(model.draft.endsOn == nil ? "Never" : "On a date")
            }
            if model.draft.endsOn != nil {
                DatePicker("Last day", selection: endBinding,
                           in: model.today.start(in: model.receiver.timeZone)...,
                           displayedComponents: .date)
                    .environment(\.timeZone, model.receiver.timeZone)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
    }

    @ViewBuilder private var prefilled: some View {
        if !model.fields.isEmpty {
            TrackerSectionLabel("PRE-FILLED ON EACH ENTRY")
                .padding(.top, 20)
                .padding(.bottom, Theme.Spacing.sm)
            ForEach(model.fields, id: \.id) { field in
                VStack(alignment: .leading, spacing: 0) {
                    heading(field.label)
                    input(for: field)
                }
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder private func input(for field: TrackerFieldInfo) -> some View {
        switch field.kind {
        case .number:
            HStack {
                ZStack(alignment: .leading) {
                    if (model.numberText[field.id] ?? "").isEmpty {
                        Text(Self.blank).foregroundStyle(Theme.Colors.textTertiary).allowsHitTesting(false)
                    }
                    TextField("", text: Binding(get: { model.numberText[field.id] ?? "" },
                                                set: { model.setNumberText($0, for: field.id) }))
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(field.label)
                }
                if let unit = field.unit, !unit.isEmpty {
                    Text(unit).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 46)
            .modifier(InputBox())
        case .text:
            StrideField(placeholder: Self.blank, text: Binding(get: { model.text(for: field.id) },
                                                               set: { model.setText($0, for: field.id) }))
        case .boolean:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    StrideChip(label: "Yes", isSelected: model.bool(for: field.id) == true) {
                        model.setBool(true, for: field.id)
                    }
                    StrideChip(label: "No", isSelected: model.bool(for: field.id) == false) {
                        model.setBool(false, for: field.id)
                    }
                }
                if model.bool(for: field.id) == nil { caption(Self.blank) }
            }
        case .choice:
            VStack(alignment: .leading, spacing: 0) {
                ChipFlow {
                    // Retired options are no longer offered.
                    ForEach(field.options.filter { !$0.retired }, id: \.id) { option in
                        StrideChip(label: option.label,
                                   isSelected: model.chosen(for: field.id).contains(option.id)) {
                            model.choose(option.id, in: field)
                        }
                    }
                }
                if model.chosen(for: field.id).isEmpty { caption(Self.blank) }
            }
        case .datetime:
            if let date = model.date(for: field.id) {
                HStack {
                    DatePicker(field.label, selection: Binding(get: { date },
                                                               set: { model.setDate($0, for: field.id) }))
                        .labelsHidden()
                        .environment(\.timeZone, model.receiver.timeZone)
                    Spacer()
                    Button("Clear") { model.setDate(nil, for: field.id) }
                        .font(.system(size: 14, weight: .semibold))
                }
            } else {
                Button { model.setDate(Date(), for: field.id) } label: {
                    HStack {
                        Text(Self.blank).foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                        Text("Set").fontWeight(.semibold).foregroundStyle(Theme.Colors.accent)
                    }
                    .font(Theme.Typography.body)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                    .modifier(InputBox())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var alert: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Alert if it goes unrecorded", isOn: $model.draft.unrecordedAlert)
                .toggleStyle(.stride)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 56)
                .modifier(AddTrackerCard())
            caption(ScheduleDraft.isTime(model.draft.time)
                    ? "Tells the team when \(TrackerText.clock(model.draft.time)) passes with nothing logged."
                    : "Tells the team when the time passes with nothing logged.")
        }
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder private var problems: some View {
        let problems = model.problems
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(problems, id: \.self) { Text($0) }
            }
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.md)
        }
    }

    // MARK: Pieces

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.bottom, Theme.Spacing.sm)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    private func menuBox(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .font(Theme.Typography.body)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 46)
        .modifier(InputBox())
    }

    // MARK: Bindings

    private static let utc = TimeZone(identifier: "UTC")!

    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let parts = model.draft.time.split(separator: ":").compactMap { Int($0) }
                let (h, m) = parts.count == 2 ? (parts[0], parts[1]) : (8, 0)
                return Self.utcCalendar.date(from: DateComponents(year: 2000, month: 1, day: 1,
                                                                  hour: h, minute: m))!
            },
            set: { date in
                let c = Self.utcCalendar.dateComponents([.hour, .minute], from: date)
                model.draft.time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { (model.draft.endsOn ?? model.today).start(in: model.receiver.timeZone) },
            set: { model.draft.endsOn = LocalDay($0, zone: model.receiver.timeZone) }
        )
    }
}

/// A form input's box: white, rounded, a hairline border.
private struct InputBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
            }
    }
}

/// Remove this schedule? (PRD; Figma 375:3671): what goes and what stays, then Remove
/// or Cancel. `onRemoved` runs once the schedule is gone, just before this sheet goes;
/// Cancel goes back to A schedule.
struct RemoveScheduleV1Sheet: View {
    let model: ScheduleSheetModel
    let onRemoved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TrackerIconTile(icon: model.trackerIcon, color: model.trackerColor, size: 40)
                    .accessibilityHidden(true)
                Text("Remove \(model.displayName)?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(Self.explanation)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.md)
            if let failed = model.removeFailed {
                StrideAlertBanner(message: "Couldn't remove the schedule. \(failed.message)")
                    .padding(.top, Theme.Spacing.md)
            }
            VStack(spacing: 12) {
                StrideButton(title: "Remove schedule", style: .destructive, isLoading: model.isRemoving) {
                    Task {
                        if await model.remove() {
                            onRemoved()
                            dismiss()
                        }
                    }
                }
                StrideButton(title: "Cancel", style: .secondary) { dismiss() }
                    .disabled(model.isRemoving)
            }
            .padding(.top, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isRemoving)
        .tint(Theme.Colors.accent)
    }

    /// What goes, then what stays (PRD "Remove this schedule?").
    static let explanation = "The schedule goes, and so does every occurrence of it still waiting. "
        + "Every entry already logged, skipped, or unrecorded stays where it is, "
        + "in the timelines it appeared in and the insights it fed."
}

#if DEBUG
@MainActor private func previewModel(_ profile: TrackerProfile, existing: TrackerScheduleItem?,
                          replacesGap: Bool = false) -> ScheduleSheetModel {
    ScheduleSheetModel(trackerID: profile.id, trackerName: profile.name, trackerIcon: profile.icon,
                       trackerColor: profile.color, fields: profile.fields, receiver: TrackersFixtures.eleanor,
                       existing: existing, replacesGap: replacesGap, gapHours: profile.gapHours,
                       service: TrackersFixtures.service())
}

#Preview("Evening") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ScheduleSheet(model: previewModel(TrackersFixtures.medication,
                                          existing: TrackersFixtures.medicationSchedules[1])) { _ in }
    }
}

#Preview("New on a gap tracker") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ScheduleSheet(model: previewModel(TrackersFixtures.weight, existing: nil, replacesGap: true)) { _ in }
    }
}

#Preview("Remove Evening?") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RemoveScheduleV1Sheet(model: previewModel(TrackersFixtures.medication,
                                                  existing: TrackersFixtures.medicationSchedules[1])) {}
    }
}
#endif
