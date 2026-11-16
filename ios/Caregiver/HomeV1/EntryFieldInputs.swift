import SwiftUI

/// An entry's fields as inputs, one per active field in the tracker's order (Figma
/// 448:4372 choice, 448:4379 text, 448:4446 a pair of numbers): a number with its unit,
/// Yes or No, a choice's options as chips (one or several), a line of text, a date and
/// time. Two numbers in a row sit side by side, as a blood pressure's do. Writes straight
/// to `values`, which does the checking.
struct EntryFieldInputs: View {
    /// Active fields only; a paused field takes no value.
    let fields: [TrackerFieldInfo]
    @Binding var values: EntryValuesDraft
    /// The receiver's, which a date and time field is entered in.
    let zone: TimeZone
    /// A line under a field's input, by field id — Edit entry's "Expected 90–140" under a
    /// value that was logged outside its range (Figma 445:4389).
    var hints: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(Self.rows(fields).enumerated()), id: \.offset) { _, row in
                if row.count == 2 {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row, id: \.id) { field in
                            labeled(field) { input(for: field) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else if let field = row.first {
                    labeled(field) { input(for: field) }
                }
            }
        }
    }

    /// The fields in rows: two numbers in a row share one, everything else has its own.
    static func rows(_ fields: [TrackerFieldInfo]) -> [[TrackerFieldInfo]] {
        var out: [[TrackerFieldInfo]] = []
        for field in fields where !field.paused {
            if field.kind == .number, let last = out.last, last.count == 1, last[0].kind == .number {
                out[out.count - 1].append(field)
            } else {
                out.append([field])
            }
        }
        return out
    }

    private func labeled<Content: View>(_ field: TrackerFieldInfo,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QuickLogFieldLabel(text: field.label)
            content()
            if let hint = hints[field.id] {
                Text(hint)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func input(for field: TrackerFieldInfo) -> some View {
        switch field.kind {
        case .number:
            HStack(spacing: Theme.Spacing.sm) {
                TextField("", text: Binding(get: { values.numberText(for: field.id) },
                                            set: { values.setNumberText($0, for: field.id) }))
                    .keyboardType(.decimalPad)
                    .accessibilityLabel(field.label)
                if let unit = field.unit, !unit.isEmpty {
                    Text(unit).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .quickLogInputBox()
        case .text:
            TextField("", text: Binding(get: { values.text(for: field.id) },
                                        set: { values.setText($0, for: field.id) }),
                      axis: .vertical)
                .lineLimit(1...4)
                .accessibilityLabel(field.label)
                .quickLogInputBox()
        case .boolean:
            HStack(spacing: Theme.Spacing.sm) {
                StrideChip(label: "Yes", isSelected: values.bool(for: field.id) == true) {
                    values.setBool(true, for: field.id)
                }
                StrideChip(label: "No", isSelected: values.bool(for: field.id) == false) {
                    values.setBool(false, for: field.id)
                }
            }
        case .choice:
            // Retired options are no longer offered.
            ChipFlow {
                ForEach(field.options.filter { !$0.retired }, id: \.id) { option in
                    StrideChip(label: option.label, isSelected: values.chosen(for: field.id).contains(option.id)) {
                        values.choose(option.id, in: field)
                    }
                }
            }
        case .datetime:
            if let date = values.date(for: field.id) {
                HStack {
                    DatePicker(field.label, selection: Binding(get: { date },
                                                               set: { values.setDate($0, for: field.id, zone: zone) }))
                        .labelsHidden()
                        .environment(\.timeZone, zone)
                    Spacer()
                    Button("Clear") { values.setDate(nil, for: field.id, zone: zone) }
                        .font(.system(size: 14, weight: .semibold))
                }
            } else {
                Button { values.setDate(Date(), for: field.id, zone: zone) } label: {
                    HStack {
                        Text("Not set").foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                        Text("Set").fontWeight(.semibold).foregroundStyle(Theme.Colors.accent)
                    }
                    .contentShape(Rectangle())
                    .quickLogInputBox()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(field.label), not set")
            }
        }
    }
}

/// "Dose", "Note": the label above an input (Figma 448:4373).
struct QuickLogFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

/// A note, or a journal note's body: several lines in a box (Figma 448:4385, 448:4488).
struct QuickLogNoteInput: View {
    var label = "Note"
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            QuickLogFieldLabel(text: label)
            TextField("", text: $text, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityLabel(label)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
        }
    }
}

extension View {
    /// Figma 448:4381: a 46pt white box with a hairline border.
    func quickLogInputBox() -> some View {
        self
            .font(.system(size: 16))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
    }
}

#if DEBUG
#Preview("Field inputs") {
    @Previewable @State var values = EntryValuesDraft(["sys": .number(128), "dia": .number(82)])
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            EntryFieldInputs(fields: HomeFixtures.bloodPressureFields, values: $values,
                             zone: HomeFixtures.chicago)
            EntryFieldInputs(fields: TrackersFixtures.medicationFields, values: $values,
                             zone: HomeFixtures.chicago)
        }
        .padding(24)
    }
    .background(Theme.Colors.surface)
}
#endif
