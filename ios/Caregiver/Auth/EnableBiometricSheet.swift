import SwiftUI

struct EnableBiometricSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onEnable: () -> Void

    private var biometryName: String { BiometricAuth.biometryName }
    private var biometryIcon: String { biometryName == "Face ID" ? "faceid" : "touchid" }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: biometryIcon)
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.accent)
            VStack(spacing: Theme.Spacing.sm) {
                Text("Sign in faster with \(biometryName)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Skip the password next time — use \(biometryName) to sign in instantly.")
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            StrideButton(title: "Enable \(biometryName)") {
                onEnable()
                dismiss()
            }
            Button("Not now") { dismiss() }
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .strideBackground()
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            EnableBiometricSheet(onEnable: {})
        }
}
