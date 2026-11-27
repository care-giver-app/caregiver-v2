import SwiftUI

/// One row on a Settings card (Figma `Stride/Settings Row`): an icon, the label, then what
/// trails it. Rows share a card, so unlike `StrideSettingsRow` this draws no card of its own.
struct SettingsRow<Trailing: View>: View {
    var icon: String?
    let label: String
    var labelColor: Color = Theme.Colors.textPrimary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == SettingsChevron {
    /// A row that leads somewhere.
    init(icon: String?, label: String, labelColor: Color = Theme.Colors.textPrimary) {
        self.init(icon: icon, label: label, labelColor: labelColor) { SettingsChevron() }
    }
}

/// The trailing chevron of a row that leads somewhere (Figma 16pt).
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Colors.textTertiary)
            .accessibilityHidden(true)
    }
}

/// A row's switch, in the app's style.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        // The stride style draws its label, so the label is for VoiceOver only.
        Toggle(isOn: $isOn) { EmptyView() }
            .toggleStyle(.stride)
            .fixedSize()
            .accessibilityLabel(label)
    }
}

/// A row that is a button: the whole row takes the tap.
struct SettingsButtonRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
    }
}

/// The gray line under a card (Figma "Caption").
struct SettingsCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.sm)
    }
}

/// A sheet's labeled input (Figma "Input: …"), with the line under it when something is
/// wrong with what is in it: the box turns red, and the line says what (Figma 482:3353).
struct SettingsInput: View {
    enum Kind { case text, email, password, newPassword, name, code }

    let label: String
    @Binding var text: String
    var kind: Kind = .text
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            field
                .font(.system(size: kind == .code ? 22 : 16, weight: kind == .code ? .medium : .regular))
                .kerning(kind == .code ? 6 : 0)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(error == nil ? Theme.Colors.border : Theme.Colors.alert, lineWidth: 1)
                }
            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var field: some View {
        switch kind {
        case .password:
            SecureField("", text: $text).textContentType(.password)
        case .newPassword:
            SecureField("", text: $text).textContentType(.newPassword)
        case .email:
            TextField("", text: $text)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .name:
            TextField("", text: $text).textContentType(.name)
        case .code:
            TextField("", text: Binding(get: { text },
                                        set: { text = String($0.filter(\.isNumber).prefix(6)) }))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        case .text:
            TextField("", text: $text)
        }
    }
}

/// A Settings form sheet (Figma 482:3423 / 481:3532 / 481:3568): Cancel (or Back), the
/// title and, when it has one, Save in its bar; then the inputs.
struct SettingsFormSheet<Content: View>: View {
    let title: String
    var leading: String = SettingsText.cancel
    var onLeading: (() -> Void)?
    var save: (title: String, enabled: Bool, action: () -> Void)?
    let isWorking: Bool
    var detents: Set<PresentationDetent> = [.medium, .large]
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Colors.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(leading) { (onLeading ?? { dismiss() })() }
                        .disabled(isWorking)
                }
                if let save {
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking {
                            ProgressView().tint(Theme.Colors.accent)
                        } else {
                            Button(save.title, action: save.action)
                                .fontWeight(.semibold)
                                .disabled(!save.enabled)
                        }
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
    }
}

/// A pushed Settings screen's frame: the gradient, "‹ Back", and the title in the bar.
struct SettingsPushedScreen: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .strideBackground()
            .toolbar(.visible, for: .navigationBar)
            .strideBackButton()
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    StrideNavTitle(title: title, subtitle: nil)
                }
            }
    }
}

extension View {
    func settingsPushedScreen(_ title: String) -> some View {
        modifier(SettingsPushedScreen(title: title))
    }
}
