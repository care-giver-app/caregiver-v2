import SwiftUI

/// Sign up (PRD "Getting into the app"; Figma 353:3209). Pushed from Landing;
/// swaps with Sign in.
struct SignUpView: View {
    @Bindable var model: AuthModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StrideBrand()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                AuthHeading(title: "Create your account", subtitle: "Start coordinating care in minutes")
                    .padding(.bottom, 18)
                HStack(spacing: 10) {
                    StrideField(placeholder: "First name", icon: "person", text: $model.firstName)
                        .textContentType(.givenName)
                    StrideField(placeholder: "Last name", icon: "person", text: $model.lastName)
                        .textContentType(.familyName)
                }
                .padding(.bottom, 12)
                StrideField(placeholder: "Email", icon: "envelope", text: $model.email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.bottom, 12)
                StrideField(placeholder: "Password", icon: "lock", isSecure: true, text: $model.password)
                    .textContentType(.newPassword)
                    .padding(.bottom, 12)
                StrideField(placeholder: "Confirm password", icon: "lock", isSecure: true,
                            text: $model.confirmPassword)
                    .textContentType(.newPassword)
                    .authBanner(model.formBanner)
                    .padding(.bottom, 20)
                StrideButton(title: "Create account", isLoading: model.isBusy) {
                    Task { await model.signUp() }
                }
                .padding(.bottom, Theme.Spacing.md)
                // Markdown links need literal URLs. They 404 until the pages are published.
                Text("By continuing, you agree to our [Terms](https://caretosher.com/terms) & [Privacy Policy](https://caretosher.com/privacy).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tint(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                Button { model.show(.signIn) } label: {
                    Text("Already have an account?  Sign in")
                        .frame(maxWidth: .infinity)
                }
                .authLinkStyle()
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
    }
}

#if DEBUG
#Preview("Sign up") {
    NavigationStack { SignUpView(model: .preview()) }
}
#endif
