import SwiftUI

/// Reset password — the content of the auth sheet over Sign in. It changes in
/// place: first the address, then the code and a new password (PRD "Getting into
/// the app"; Figma 357:3303, 357:3322, code not right 357:3363). `AuthSheetView`
/// supplies the sheet chrome.
struct ResetPasswordView: View {
    @Bindable var model: AuthModel
    let step: ResetStep

    var body: some View {
        switch step {
        case .address: address
        case .codeAndPassword: codeAndPassword
        }
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthHeading(title: "Reset password", subtitle: "Enter your email")
                .padding(.bottom, 20)
            StrideField(placeholder: "Email", icon: "envelope", text: $model.email)
                .textContentType(.username).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .authBanner(model.sheetBanner)
                .padding(.bottom, 20)
            StrideButton(title: "Send me a code", isLoading: model.isBusy) {
                Task { await model.sendResetCode() }
            }
            .padding(.bottom, Theme.Spacing.md)
            Button { model.dismissSheet() } label: {
                Text("Back to sign in").frame(maxWidth: .infinity)
            }
            .authLinkStyle()
            .disabled(model.isBusy)
        }
    }

    private var codeAndPassword: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthHeading(title: "Check your email")
                .padding(.bottom, 12)
            // The same answer for every address, so nobody can learn which have
            // accounts (PRD).
            StrideAlertBanner(message: AuthModel.Copy.resetCodeSent, tone: .info)
                .padding(.bottom, 18)
            StrideCodeInput(code: $model.code)
                .frame(maxWidth: .infinity)
                .authBanner(model.sheetBanner)
                .padding(.bottom, 12)
            StrideField(placeholder: "New password", icon: "lock", isSecure: true, text: $model.newPassword)
                .textContentType(.newPassword)
                .padding(.bottom, 20)
            StrideButton(title: "Set new password", isLoading: model.isBusy) {
                Task { await model.setNewPassword() }
            }
            .padding(.bottom, Theme.Spacing.md)
            Button { model.backToAddress() } label: {
                Text("Back to the address").frame(maxWidth: .infinity)
            }
            .authLinkStyle()
            .disabled(model.isBusy)
        }
    }
}

#if DEBUG
#Preview("Reset password · address") {
    Color.clear
        .strideAuthBackground()
        .sheet(isPresented: .constant(true)) {
            AuthSheetView(model: .preview(sheet: .resetPassword(.address)))
        }
}

#Preview("Reset password · code not right") {
    Color.clear
        .strideAuthBackground()
        .sheet(isPresented: .constant(true)) {
            AuthSheetView(model: .preview(sheet: .resetPassword(.codeAndPassword),
                                          sheetBanner: .error(AuthModel.Copy.resetCodeNotRight)))
        }
}
#endif
