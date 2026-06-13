import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthModel
    var onSwitchToSignIn: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Create account").font(Theme.Typography.largeTitle)
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password (8+ chars)", text: $model.password)
                .textContentType(.newPassword)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Sign up", isLoading: model.isBusy) {
                Task { await model.signUp() }
            }
            Button("I already have an account", action: onSwitchToSignIn)
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.accent)
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(Theme.Spacing.lg)
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
    }
}
