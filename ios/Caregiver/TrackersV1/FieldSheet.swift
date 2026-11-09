import SwiftUI

/// A field (PRD "A field"; Figma 374:3472 before the tracker exists, 374:3530 after): one
/// piece of data a tracker captures, as a sheet over Add tracker or Edit tracker. It edits
/// a copy; Save hands the copy back through `onSave`, Cancel drops it. `onRemove` is
/// passed only while the tracker does not exist yet, and shows Remove.
struct FieldSheet: View {
    let onSave: (FieldDraft) -> Void
    let onRemove: (() -> Void)?

    @State private var editor: FieldEditor
    @Environment(\.dismiss) private var dismiss

    init(field: FieldDraft, onSave: @escaping (FieldDraft) -> Void, onRemove: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onRemove = onRemove
        _editor = State(initialValue: FieldEditor(field: field))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading("Name")
                    StrideField(placeholder: "Such as Systolic", text: $editor.label)
                    heading("Type").padding(.top, Theme.Spacing.md)
                    typeChips
                    kindSpecific
                    required
                    if editor.draft.kind == .number { range }
                    problems
                    if let onRemove {
                        StrideButton(title: "Remove", style: .destructive) {
                            onRemove()
                            dismiss()
                        }
                        .padding(.top, Theme.Spacing.lg)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.surface)
            .navigationTitle("Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editor.field)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!editor.canSave)
                }
            }
        }
    }

    // MARK: Parts

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.bottom, Theme.Spacing.sm)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.top, Theme.Spacing.sm)
    }

    private var typeChips: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChipFlow {
                ForEach(FieldEditor.kinds, id: \.self) { kind in
                    StrideChip(label: kind.chipTitle, isSelected: editor.draft.kind == kind) {
                        editor.setKind(kind)
                    }
                    .disabled(editor.kindLocked && editor.draft.kind != kind)
                    .opacity(editor.kindLocked && editor.draft.kind != kind ? 0.45 : 1)
                }
            }
            if editor.kindLocked {
                caption("A field's type can't change once the tracker has it.")
            }
        }
    }

    @ViewBuilder private var kindSpecific: some View {
        switch editor.draft.kind {
        case .number:
            heading("Unit").padding(.top, Theme.Spacing.md)
            StrideField(placeholder: "mmHg", text: $editor.unit)
            caption("Such as mmHg, lb, or °F.")
        case .choice:
            choice
        case .text, .boolean, .datetime:
            EmptyView()
        }
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Answers").padding(.top, Theme.Spacing.md)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach([false, true], id: \.self) { several in
                    StrideChip(label: several ? "Several answers" : "One answer",
                               isSelected: editor.multiple == several) { editor.multiple = several }
                        .disabled(editor.kindLocked && editor.multiple != several)
                        .opacity(editor.kindLocked && editor.multiple != several ? 0.45 : 1)
                }
            }
            heading("Options").padding(.top, Theme.Spacing.md)
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(editor.options) { option in
                    optionRow(option)
                }
            }
            Button {
                editor.addOption()
            } label: {
                Label("Add an option", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(.top, Theme.Spacing.md)
        }
    }

    private func optionRow(_ option: OptionDraft) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            StrideField(placeholder: "Option", text: Binding(
                get: { editor.options.first { $0.id == option.id }?.label ?? "" },
                set: { editor.renameOption(option.id, to: $0) }
            ))
            .opacity(option.retired ? 0.5 : 1)
            if editor.canDelete(option) {
                Button { editor.deleteOption(option.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Colors.alert)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete option")
            } else {
                Button(option.retired ? "Bring back" : "Retire") {
                    editor.setRetired(option.id, !option.retired)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(.plain)
            }
        }
    }

    private var required: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleCard("Required", isOn: $editor.required)
            caption("A caregiver can't save an entry without it.")
        }
        .padding(.top, Theme.Spacing.md)
    }

    private var range: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleCard("Alert when out of range", isOn: $editor.alertsOutOfRange)
            if editor.alertsOutOfRange {
                HStack(spacing: 12) {
                    bound("Low", text: $editor.lowText)
                    bound("High", text: $editor.highText)
                }
                .padding(.top, Theme.Spacing.md)
                RangeBar(low: editor.low, high: editor.high)
                    .padding(.top, Theme.Spacing.md)
                if let sentence = editor.rangeSentence {
                    caption(sentence)
                }
            }
        }
        .padding(.top, Theme.Spacing.md)
    }

    private func toggleCard(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.stride)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 56)
            .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
    }

    private func bound(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(title)
            HStack {
                TextField("", text: text)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel(title)
                let unit = editor.unit.trimmingCharacters(in: .whitespaces)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 46)
            .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
            }
        }
    }

    @ViewBuilder private var problems: some View {
        let problems = editor.problems
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(problems, id: \.self) { Text($0) }
            }
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.alert)
            .padding(.top, Theme.Spacing.md)
        }
    }
}

/// Alert, expected, alert: the readings that would alert the team either side of the
/// range a number is expected to stay inside. A side with no bound draws no alert.
private struct RangeBar: View {
    let low: Double?
    let high: Double?

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let gap: CGFloat = 4
                let side = geo.size.width * 0.18
                HStack(spacing: gap) {
                    Capsule().fill(Theme.Colors.alertTint).frame(width: side).opacity(low == nil ? 0 : 1)
                    Capsule().fill(Theme.Colors.success)
                    Capsule().fill(Theme.Colors.alertTint).frame(width: side).opacity(high == nil ? 0 : 1)
                }
                .overlay(alignment: .topLeading) {
                    HStack {
                        Text(FieldEditor.format(low)).offset(x: side - 8)
                        Spacer()
                        Text(FieldEditor.format(high)).offset(x: -side + 8)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .offset(y: 12)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Alert").opacity(low == nil ? 0 : 1)
                Spacer()
                Text("Expected").foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("Alert").opacity(high == nil ? 0 : 1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.Colors.alert)
            .padding(.top, 18)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .accessibilityHidden(true)
    }
}

/// Lays chips in rows, wrapping when a row is full.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

#if DEBUG
private let systolic = FieldDraft(label: "Systolic", kind: .number, unit: "mmHg", required: true,
                                  alertsOutOfRange: true, low: 90, high: 140)

#Preview("New tracker") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FieldSheet(field: systolic, onSave: { _ in }, onRemove: {})
    }
}

#Preview("Existing tracker") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FieldSheet(field: FieldDraft(TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg",
                                                      options: [])),
                   onSave: { _ in })
    }
}

#Preview("Existing choice") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FieldSheet(field: FieldDraft(TrackersFixtures.medicationFields[1]), onSave: { _ in })
    }
}

#Preview("New field, blank") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FieldSheet(field: FieldDraft(label: "", kind: .text), onSave: { _ in }, onRemove: {})
    }
}
#endif
