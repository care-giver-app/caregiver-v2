import SwiftUI

/// Shared field-row renderer for a `FieldInput` — one enum-tile / number+unit /
/// text / bool / datetime row, styled with Aurora's `StrideField` system. Used by
/// both the quick-log wizard's detail step and the single-event log/edit sheet so
/// the two entry points render identically.
struct DynamicFieldRow: View {
    @Binding var input: FieldInput
    var error: String?

    private enum Metrics {
        static let boxRadius: CGFloat = 14
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            switch input.kind {
            case .enumeration:
                Text(input.label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                scaleTiles
            case .number:
                StrideField(placeholder: input.label, text: $input.textValue)
                    .keyboardType(.decimalPad)
                    .overlay(alignment: .trailing) {
                        if let unit = input.unit {
                            Text(unit)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.trailing, Theme.Spacing.md)
                        }
                    }
            case .text:
                StrideField(placeholder: input.label, text: $input.textValue)
            case .boolean:
                Toggle(input.label, isOn: $input.boolValue)
                    .toggleStyle(.stride)
                    .foregroundStyle(Theme.Colors.textPrimary)
            case .datetime:
                StrideDatePicker(label: input.label, selection: $input.dateValue)
            }
            if let error {
                Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.alert)
            }
        }
    }

    /// Equal-width scale tiles for `.enumeration` fields, matching `StrideSelectTile`'s
    /// selected treatment (accent fill + accent border).
    private var scaleTiles: some View {
        HStack(spacing: 10) {
            ForEach(input.options, id: \.self) { option in
                let isSelected = input.textValue == option
                Button {
                    input.textValue = option
                } label: {
                    Text(option)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.Colors.textOnAccent : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                                .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                                .stroke(isSelected ? Theme.Colors.accent : Theme.Colors.border,
                                        lineWidth: isSelected ? 1.5 : 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
