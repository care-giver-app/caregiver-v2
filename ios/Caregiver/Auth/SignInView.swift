import SwiftUI

/// Sign in (PRD "Getting into the app"; Figma 355:3212, credentials incorrect
/// 355:3246, locked 355:3278). Pushed from Landing; swaps with Sign up.
struct SignInView: View {
    @Bindable var model: AuthModel

    @AppStorage("rememberEmail") private var rememberEmail = false
    @AppStorage("savedEmail") private var savedEmail = ""
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var canUseBiometrics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StrideBrand()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                AuthHeading(title: "Welcome back", subtitle: "Sign in to coordinate care with your team")
                    .padding(.bottom, 18)
                StrideField(placeholder: "Email", icon: "envelope", text: $model.email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.bottom, 12)
                StrideField(placeholder: "Password", icon: "lock", isSecure: true, text: $model.password)
                    .textContentType(.password)
                    .authBanner(model.formBanner)
                    .padding(.bottom, 14)
                HStack(spacing: Theme.Spacing.sm) {
                    Toggle("", isOn: $rememberEmail)
                        .toggleStyle(.stride)
                        .labelsHidden()
                        .fixedSize()
                    Text("Remember me")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    // Available throughout, the lock included: it does not depend on
                    // remembering anything (PRD).
                    Button("Forgot password?") { model.openResetPassword() }
                        .authLinkStyle()
                }
                .padding(.bottom, 18)
                StrideButton(title: "Sign in", isLoading: model.isBusy) {
                    savedEmail = rememberEmail ? model.email : ""
                    Task { await model.signIn() }
                }
                if canUseBiometrics {
                    StrideButton(title: "Use \(BiometricAuth.biometryName)", style: .secondary) {
                        Task {
                            let granted = await BiometricAuth.authenticate(reason: "Sign in to CareToSher")
                            if granted { await model.signInWithBiometrics() }
                            refreshBiometrics()
                        }
                    }
                    .disabled(model.isBusy)
                    .padding(.top, 12)
                }
                Button { model.show(.signUp) } label: {
                    Text("New to CareToSher?  Create account")
                        .frame(maxWidth: .infinity)
                }
                .authLinkStyle()
                .padding(.top, 20)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .strideAuthBackground()
        .toolbar(.visible, for: .navigationBar)
        .strideBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Theme.Colors.accent)
        .onAppear {
            // Remember me stores the email only. An address already filled in — sent
            // here from Sign up, say — wins over the remembered one.
            if model.email.isEmpty && !savedEmail.isEmpty { model.email = savedEmail }
            refreshBiometrics()
        }
        .onChange(of: faceIDEnabled) { refreshBiometrics() }
    }

    /// Face ID shows when the device has it and a password is stored (PRD).
    private func refreshBiometrics() {
        canUseBiometrics = faceIDEnabled && BiometricAuth.isAvailable && model.hasStoredCredentials
    }
}

#if DEBUG
#Preview("Sign in") {
    NavigationStack { SignInView(model: .preview()) }
}

#Preview("Sign in · credentials incorrect") {
    NavigationStack {
        SignInView(model: .preview(formBanner: .error(AuthModel.Copy.incorrectCredentials)))
    }
}

#Preview("Sign in · locked") {
    NavigationStack { SignInView(model: .preview(formBanner: .error(AuthModel.Copy.locked))) }
}

#Preview("Sign in · already has an account") {
    NavigationStack { SignInView(model: .preview(formBanner: .info(AuthModel.Copy.alreadyHasAccount))) }
}
#endif
