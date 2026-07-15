import SwiftUI

/// A Settings list row (Figma `Stride/Settings Row`, set `158:620`): 20pt SF Symbol
/// + 15pt medium label + one of five trailing accessories. Navigation/selection
/// taps belong to the consumer (wrap the row in a `Button`); only `.toggle` is
/// interactive by itself, binding through `StrideToggleStyle`.
struct StrideSettingsRow: View {
    enum Trailing {
        case none
        case chevron
        case check
        case value(String)
        case toggle(Binding<Bool>)
    }

    let icon: String
    let label: String
    var trailing: Trailing = .chevron

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            switch trailing {
            case .none:
                EmptyView()
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            case .check:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            case .value(let value):
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            case .toggle(let isOn):
                Toggle(isOn: isOn) { EmptyView() }
                    .toggleStyle(.stride)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Trailing variants") {
    @Previewable @State var reminders = true
    VStack(spacing: 10) {
        StrideSettingsRow(icon: "person.2", label: "The Riverside Group", trailing: .check)
        StrideSettingsRow(icon: "person.2", label: "Johnson Family", trailing: .none)
        StrideSettingsRow(icon: "person.crop.circle", label: "Account")
        StrideSettingsRow(icon: "info.circle", label: "Version", trailing: .value("2.0.0"))
        StrideSettingsRow(icon: "bell", label: "Reminders", trailing: .toggle($reminders))
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
