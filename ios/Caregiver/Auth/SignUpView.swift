import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthModel
    var onSignIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md - 2) {
                StrideBrand()
                    .padding(.bottom, Theme.Spacing.xs)
                VStack(spacing: 6) {
                    Text("Create your account")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Start coordinating care in minutes.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Spacing.xs)
                HStack(spacing: 10) {
                    StrideField(placeholder: "First name", icon: "person", text: $model.firstName)
                        .textContentType(.givenName)
                    StrideField(placeholder: "Last name", icon: "person", text: $model.lastName)
                        .textContentType(.familyName)
                }
                StrideField(placeholder: "Email", icon: "envelope", text: $model.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                StrideField(placeholder: "Password (8+ chars)", icon: "lock", isSecure: true, text: $model.password)
                    .textContentType(.newPassword)
                StrideField(placeholder: "Confirm password", icon: "lock", isSecure: true, text: $model.confirmPassword)
                    .textContentType(.newPassword)
                if let error = model.error {
                    Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
                }
                StrideButton(title: "Create account", isLoading: model.isBusy) {
                    Task { await model.signUp() }
                }
                .padding(.top, Theme.Spacing.xs + 2)
                Text("By continuing, you agree to our [Terms](https://caregiver.app/terms) & [Privacy Policy](https://caregiver.app/privacy).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tint(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 5) {
                    Text("Already have an account?")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Sign in", action: onSignIn)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .font(.system(size: 14))
            }
            .padding(Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .strideAuroraBackground()
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
    }
}

#Preview {
    SignUpView(model: AuthModel(), onSignIn: {})
}
