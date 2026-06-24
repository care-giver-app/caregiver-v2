import SwiftUI

struct AuthLandingView: View {
    var onSignIn: () -> Void
    var onSignUp: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .padding(.horizontal, Theme.Spacing.lg)
            Spacer()
            StrideButton(title: "Sign In", action: onSignIn)
            StrideButton(title: "Create Account", style: .secondary, action: onSignUp)
            Link("Need help? Contact support", destination: URL(string: "mailto:support@caregiver.app")!)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.ink.opacity(0.5))
        }
        .padding(Theme.Spacing.lg)
        .earthBackground()
    }
}

#Preview {
    AuthLandingView(onSignIn: {}, onSignUp: {})
}
