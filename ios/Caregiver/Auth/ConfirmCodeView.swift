import SwiftUI

struct ConfirmCodeView: View {
    @Bindable var model: AuthModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.sm) {
                Text("Check your email")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Enter the 6-digit code we sent to \(model.email).")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Spacing.lg)

            StrideCodeInput(code: $model.code)
                .padding(.vertical, Theme.Spacing.sm)

            if let error = model.error {
                Text(error.message)
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.alert)
            }

            StrideButton(title: "Confirm", isLoading: model.isBusy) {
                Task { await model.confirm() }
            }

            HStack(spacing: 5) {
                Text("Didn't get a code?")
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("Resend") { Task { await model.resendCode() } }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .font(.system(size: 14))

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .strideAuroraBackground()
        .presentationDetents([.medium])
        .presentationCornerRadius(24)
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            ConfirmCodeView(model: {
                let m = AuthModel()
                m.email = "trevor@example.com"
                return m
            }())
        }
}
