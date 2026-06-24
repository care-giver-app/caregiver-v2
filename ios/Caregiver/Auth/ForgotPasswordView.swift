import SwiftUI

struct ForgotPasswordView: View {
    @Bindable var model: AuthModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text(model.resetCodeSent ? "Check your email" : "Reset password")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.ink)
                    Text(model.resetCodeSent
                         ? "Enter the code we sent to \(model.email) and choose a new password."
                         : "Enter your email and we'll send you a reset code.")
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.lg)

                if model.resetCodeSent {
                    StrideField(placeholder: "Reset code", icon: "number", text: $model.code)
                        .keyboardType(.numberPad)
                    StrideField(placeholder: "New password", icon: "lock", isSecure: true, text: $model.newPassword)
                        .textContentType(.newPassword)
                } else {
                    StrideField(placeholder: "Email", icon: "envelope", text: $model.email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }

                if let error = model.error {
                    Text(error.message)
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.alert)
                }

                StrideButton(
                    title: model.resetCodeSent ? "Set new password" : "Send reset code",
                    isLoading: model.isBusy
                ) {
                    Task {
                        if model.resetCodeSent {
                            await model.confirmReset()
                            if model.error == nil { dismiss() }
                        } else {
                            await model.sendResetCode()
                        }
                    }
                }

                Button("Cancel") { dismiss() }
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.ink.opacity(0.6))

                Spacer()
            }
        .padding(Theme.Spacing.lg)
        .earthBackground()
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
        .onAppear {
            model.resetCodeSent = false
            model.code = ""
            model.newPassword = ""
            model.error = nil
        }
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            ForgotPasswordView(model: AuthModel())
        }
}
