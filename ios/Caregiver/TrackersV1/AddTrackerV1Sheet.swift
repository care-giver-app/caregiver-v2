import SwiftUI

/// Add tracker (PRD "Add tracker"; Figma 370:3265 choose, 370:3329 adjust, 408:3745 icon
/// and color): one sheet whose parts swap in place in its own NavigationStack. Create
/// hands the new tracker to `onCreated` and dismisses; the raiser pushes it.
struct AddTrackerV1Sheet: View {
    let onCreated: (TrackerProfile) -> Void

    @State private var model: AddTrackerV1Model
    /// The field A field is open on.
    @State private var editing: FieldDraft?
    @Environment(\.dismiss) private var dismiss

    init(receiver: TeamReceiver, service: TrackersService, onCreated: @escaping (TrackerProfile) -> Void) {
        self.onCreated = onCreated
        _model = State(initialValue: AddTrackerV1Model(receiver: receiver, service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.part {
                case .choose: choose
                case .adjust: adjust
                case .iconColor:
                    TrackerIconColorPart(icon: $model.draft.icon, color: $model.draft.color,
                                         name: model.draft.name) { model.part = .adjust }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(model.isCreating)
        .task { await model.loadTemplates() }
        .sheet(item: $editing) { field in
            // Remove is only for a field already on the draft; a new one is just cancelled.
            FieldSheet(field: field, onSave: { model.draft.upsert($0) },
                       onRemove: model.draft.fields.contains { $0.id == field.id }
                           ? { model.remove(field.id) } : nil)
        }
    }

    // MARK: Choose a template

    private var choose: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned above the templates, so it is never far (PRD).
            Button { model.startFromScratch() } label: {
                AddTrackerActionRow(title: "Start from scratch")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            TrackerSectionLabel("TEMPLATES")
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, 20)
                .padding(.bottom, Theme.Spacing.sm)
            templates
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.surface)
        .navigationTitle("Add a tracker")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var templates: some View {
        switch model.templates {
        case .loading:
            StrideLoadingView()
        case .failed:
            StrideErrorState(message: "Couldn't load templates.") {
                Task { await model.retryTemplates() }
            }
        case .loaded(let templates):
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(templates) { template in
                        Button { model.choose(template) } label: {
                            StrideTrackerRow(name: template.name, hue: Color(hex: template.color),
                                             icon: template.icon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    // MARK: Adjust

    private var adjust: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button { model.part = .iconColor } label: {
                        TrackerIconPreview(icon: model.draft.icon, color: model.draft.color)
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Icon and color")
                    StrideField(placeholder: "Name", text: $model.draft.name)
                }
                TrackerSectionLabel("FIELDS").padding(.top, 20)
                Text("Fields can't be deleted once the tracker is created, but they can be paused.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.sm)
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(model.draft.fields) { field in
                        fieldRow(field)
                    }
                    Button { editing = FieldDraft.blank() } label: {
                        AddTrackerActionRow(title: "Add a field")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { createBar }
        .background(Theme.Colors.surface)
        .navigationTitle("New tracker")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.back() } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .accessibilityElement(children: .combine)
                }
                .disabled(model.isCreating)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(model.isCreating)
            }
        }
    }

    /// Figma `Stride/Field Row` Mode=Removable (405:3234).
    private func fieldRow(_ field: FieldDraft) -> some View {
        HStack(spacing: 12) {
            Button { model.remove(field.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.Colors.alert)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(field.label)")
            Button { editing = field } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label.isEmpty ? "Unnamed field" : field.label)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(field.rowSummary)
                            .font(Theme.Typography.subhead)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .modifier(AddTrackerCard())
    }

    private var createBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let failed = model.createFailed {
                StrideAlertBanner(message: "Couldn't create the tracker. \(failed.message)")
            }
            if !model.problems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.problems, id: \.self) { problem in
                        Text(problem)
                    }
                }
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            StrideButton(title: "Create", isLoading: model.isCreating) {
                Task {
                    if let made = await model.create() {
                        onCreated(made)
                        dismiss()
                    }
                }
            }
            .disabled(!model.canCreate)
            .opacity(model.problems.isEmpty ? 1 : 0.5)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }
}

/// A section's small-caps label ("FIELDS", "GAP", "SCHEDULES") on Add tracker, Edit
/// tracker and A schedule.
struct TrackerSectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

/// The 56pt tile with its pencil badge, opening the icon and color part (Add tracker,
/// Edit tracker).
struct TrackerIconPreview: View {
    let icon: String
    let color: String

    var body: some View {
        TrackerIconTile(icon: icon, color: color, size: 56)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .offset(x: 4, y: 4)
            }
    }
}

/// Start from scratch, Add a field and Add a schedule (here and on Edit tracker): a plus on the accent tint, the action in accent.
struct AddTrackerActionRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.accentTint)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .modifier(AddTrackerCard())
    }
}

/// The bordered white card every row here sits on, as `StrideTrackerRow` draws it.
struct AddTrackerCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1)
            }
    }
}

#if DEBUG
#Preview("Choose a template") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddTrackerV1Sheet(receiver: TrackersFixtures.eleanor, service: TrackersFixtures.service()) { _ in }
    }
}

#Preview("Templates fail") {
    var service = TrackersFixtures.service()
    service.listTemplates = { throw TrackersFixtures.Unreachable() }
    return Color.clear.sheet(isPresented: .constant(true)) {
        AddTrackerV1Sheet(receiver: TrackersFixtures.eleanor, service: service) { _ in }
    }
}
#endif
