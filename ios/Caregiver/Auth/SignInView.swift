import SwiftUI

struct SignInView: View {
    @Bindable var model: AuthModel
    var onSwitchToSignUp: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Sign in").font(Theme.Typography.largeTitle)
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Password", text: $model.password)
                .textContentType(.password)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Sign in", isLoading: model.isBusy) {
                Task { await model.signIn() }
            }
            Button("Create an account", action: onSwitchToSignUp)
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.accent)
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(Theme.Spacing.lg)
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
    }
}
