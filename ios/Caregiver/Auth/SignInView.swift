import SwiftUI

struct SignInView: View {
    @Bindable var model: AuthModel
    var onBack: () -> Void

    @AppStorage("rememberEmail") private var rememberEmail = false
    @AppStorage("savedEmail") private var savedEmail = ""
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                StrideField(placeholder: "Email", icon: "person.crop.circle", text: $model.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                StrideField(placeholder: "Password", icon: "lock", isSecure: true, text: $model.password)
                    .textContentType(.password)
                HStack {
                    Text("Remember me")
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $rememberEmail)
                        .tint(Theme.Colors.accent)
                        .labelsHidden()
                }
                HStack {
                    Spacer()
                    Button("Forgot password?") { showForgotPassword = true }
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let error = model.error {
                    Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
                }
                StrideButton(title: "Sign In", isLoading: model.isBusy) {
                    savedEmail = rememberEmail ? model.email : ""
                    Task { await model.signIn() }
                }
                if faceIDEnabled {
                    StrideButton(title: "Sign in with \(BiometricAuth.biometryName)", style: .secondary) {
                        Task {
                            let granted = await BiometricAuth.authenticate(reason: "Sign in to Caregiver")
                            if granted { await model.signInWithBiometrics() }
                        }
                    }
                }
                Button("Back", action: onBack)
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Link("Need help? Contact support", destination: URL(string: "mailto:support@caregiver.app")!)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
            }
        .padding(Theme.Spacing.lg)
        .strideBackground()
        .onAppear { if !savedEmail.isEmpty { model.email = savedEmail } }
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
        .sheet(isPresented: $showForgotPassword) { ForgotPasswordView(model: model) }
    }
}

#Preview {
    SignInView(model: AuthModel(), onBack: {})
}
