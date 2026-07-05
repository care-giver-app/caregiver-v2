import SwiftUI

struct StrideField: View {
    let placeholder: String
    var icon: String? = nil
    var isSecure: Bool = false
    @Binding var text: String

    private enum Metrics {
        static let height: CGFloat = 56
        static let radius: CGFloat = 16
        static let iconSize: CGFloat = 20
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md - 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Metrics.iconSize)
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .allowsHitTesting(false)
                }
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
        }
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: Metrics.height)
        .background {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .stroke(Theme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 2.5, y: 3)
    }
}

#Preview("Empty + filled + secure") {
    @Previewable @State var email = ""
    @Previewable @State var name = "Eleanor"
    @Previewable @State var password = "hunter2"
    VStack(spacing: Theme.Spacing.md) {
        StrideField(placeholder: "Email", icon: "envelope", text: $email)
        StrideField(placeholder: "Name", icon: "person", text: $name)
        StrideField(placeholder: "Password", icon: "lock", isSecure: true, text: $password)
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
