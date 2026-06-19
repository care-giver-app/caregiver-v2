import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthModel
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                HStack(spacing: Theme.Spacing.sm) {
                    GlassField(placeholder: "First name", text: $model.firstName)
                        .textContentType(.givenName)
                    GlassField(placeholder: "Last name", text: $model.lastName)
                        .textContentType(.familyName)
                }
                GlassField(placeholder: "Email", icon: "person.crop.circle", text: $model.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                GlassField(placeholder: "Password (8+ chars)", icon: "lock", isSecure: true, text: $model.password)
                    .textContentType(.newPassword)
                GlassField(placeholder: "Confirm password", icon: "lock", isSecure: true, text: $model.confirmPassword)
                    .textContentType(.newPassword)
                if let error = model.error {
                    Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
                }
                PrimaryButton(title: "Create Account", isLoading: model.isBusy) {
                    Task { await model.signUp() }
                }
                Button("Back", action: onBack)
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                Link("Need help? Contact support", destination: URL(string: "mailto:support@caregiver.app")!)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.ink.opacity(0.5))
                HStack(spacing: Theme.Spacing.xs) {
                    Link("Terms of Service", destination: URL(string: "https://caregiver.app/terms")!)
                    Text("·").foregroundStyle(Theme.Colors.ink.opacity(0.4))
                    Link("Privacy Policy", destination: URL(string: "https://caregiver.app/privacy")!)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.ink.opacity(0.5))
                Spacer()
            }
        .padding(Theme.Spacing.lg)
        .earthBackground()
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
    }
}

#Preview {
    SignUpView(model: AuthModel(), onBack: {})
}
