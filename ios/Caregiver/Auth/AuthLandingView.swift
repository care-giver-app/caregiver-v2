import SwiftUI

struct AuthLandingView: View {
    var onSignIn: () -> Void
    var onSignUp: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md + 4) {
            StrideBrand()
            Text("Shared care for the people you love.")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("One calm place for your whole care team.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 14) {
                StrideButton(title: "Sign in", action: onSignIn)
                StrideButton(title: "Create account", style: .secondary, action: onSignUp)
                Link("Need help? Contact support", destination: URL(string: "mailto:support@caregiver.app")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
        .strideAuroraBackground()
    }
}

#Preview {
    AuthLandingView(onSignIn: {}, onSignUp: {})
}
