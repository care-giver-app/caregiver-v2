import SwiftUI

/// Landing — the app before it knows who you are (PRD "Getting into the app";
/// Figma 353:3192). Sign in and Create account push; contact support leaves for
/// the mail app.
struct AuthLandingView: View {
    var onSignIn: () -> Void
    var onSignUp: () -> Void

    static let supportAddress = "support@caretosher.com"

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            StrideBrand()
                .padding(.bottom, Theme.Spacing.lg)
            AuthHeading(title: "Shared care for the people you love",
                        alignment: .center)
                .padding(.bottom, Theme.Spacing.sm)
            Text("Collaborate with your care team in just one place")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: Theme.Spacing.lg)
            StrideButton(title: "Sign in", action: onSignIn)
                .padding(.bottom, 14)
            StrideButton(title: "Create account", style: .secondary, action: onSignUp)
                .padding(.bottom, 26)
            // The address is shown, not only offered as a button: a device with no
            // mail app configured would otherwise do nothing on the tap (PRD).
            Button("Need help? Contact support") {
                openURL(URL(string: "mailto:\(Self.supportAddress)")!)
            }
            .authLinkStyle()
            Text(Self.supportAddress)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textTertiary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
        .strideAuthBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        AuthLandingView(onSignIn: {}, onSignUp: {})
    }
}
