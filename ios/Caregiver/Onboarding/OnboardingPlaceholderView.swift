import SwiftUI

struct OnboardingPlaceholderView: View {
    let userName: String
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Welcome, \(userName)").font(Theme.Typography.title)
            Text("Next: create your care group (coming in the features build).")
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
    }
}
