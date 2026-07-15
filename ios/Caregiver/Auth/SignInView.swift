import SwiftUI

struct SignInView: View {
    @Bindable var model: AuthModel
    var onCreateAccount: () -> Void

    @AppStorage("rememberEmail") private var rememberEmail = false
    @AppStorage("savedEmail") private var savedEmail = ""
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var showForgotPassword = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                StrideBrand()
                    .padding(.bottom, Theme.Spacing.md)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome back")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Sign in to coordinate care with your family.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Theme.Spacing.sm)
                StrideField(placeholder: "Email", icon: "person", text: $model.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                StrideField(placeholder: "Password", icon: "lock", isSecure: true, text: $model.password)
                    .textContentType(.password)
                HStack(spacing: Theme.Spacing.sm) {
                    Toggle("", isOn: $rememberEmail)
                        .toggleStyle(.stride)
                        .labelsHidden()
                        .fixedSize()
                    Text("Remember me")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Button("Forgot password?") { showForgotPassword = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                if let error = model.error {
                    Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
                }
                StrideButton(title: "Sign in", isLoading: model.isBusy) {
                    savedEmail = rememberEmail ? model.email : ""
                    Task { await model.signIn() }
                }
                .padding(.top, Theme.Spacing.sm)
                if faceIDEnabled {
                    StrideButton(title: "Sign in with \(BiometricAuth.biometryName)", style: .secondary) {
                        Task {
                            let granted = await BiometricAuth.authenticate(reason: "Sign in to CareToSher")
                            if granted { await model.signInWithBiometrics() }
                        }
                    }
                }
                HStack(spacing: 5) {
                    Text("New to CareToSher?")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Create account", action: onCreateAccount)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .font(.system(size: 14))
                .padding(.top, Theme.Spacing.xs)
                Link("Need help? Contact support", destination: URL(string: "mailto:support@caregiver.app")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .strideAuroraBackground()
        .onAppear { if !savedEmail.isEmpty { model.email = savedEmail } }
        .sheet(isPresented: $model.needsConfirmation) { ConfirmCodeView(model: model) }
        .sheet(isPresented: $showForgotPassword) { ForgotPasswordView(model: model) }
    }
}

#Preview {
    SignInView(model: AuthModel(), onCreateAccount: {})
}
