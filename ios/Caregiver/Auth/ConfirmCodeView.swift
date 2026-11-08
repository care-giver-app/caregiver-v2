import SwiftUI

/// Confirm code — the content of the auth sheet, raised over Sign in or Sign up, or
/// in place of Reset password (PRD "Getting into the app"; Figma 356:3244, wrong
/// code 356:3278, expired 356:3315). `AuthSheetView` supplies the sheet chrome.
struct ConfirmCodeView: View {
    @Bindable var model: AuthModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthHeading(title: "Check your email",
                        subtitle: "Enter the 6-digit code we sent to \(model.email).")
                .padding(.bottom, 20)
            StrideCodeInput(code: $model.code)
                .frame(maxWidth: .infinity)
                .authBanner(model.sheetBanner, spacing: 14)
                .padding(.bottom, 20)
            StrideButton(title: "Confirm", isLoading: model.isBusy) {
                Task { await model.confirmCode() }
            }
            .padding(.bottom, Theme.Spacing.md)
            resend
        }
    }

    /// Resend is available again sixty seconds after the last code was sent (PRD).
    private var resend: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = model.resendSecondsRemaining(at: context.date)
            Button {
                Task { await model.resendCode() }
            } label: {
                Text(seconds > 0 ? "Didn't get a code?  Resend in \(seconds)s" : "Didn't get a code?  Resend")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .authLinkStyle()
            .disabled(seconds > 0 || model.isBusy)
        }
    }
}

#if DEBUG
#Preview("Confirm code") {
    Color.clear
        .strideAuthBackground()
        .sheet(isPresented: .constant(true)) {
            AuthSheetView(model: .preview(sheet: .confirmCode(.signUp)))
        }
}

#Preview("Confirm code · wrong code") {
    Color.clear
        .strideAuthBackground()
        .sheet(isPresented: .constant(true)) {
            AuthSheetView(model: .preview(sheet: .confirmCode(.signUp),
                                          sheetBanner: .error(AuthModel.Copy.codeIncorrect)))
        }
}
#endif
