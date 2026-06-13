import SwiftUI

struct DashboardPlaceholderView: View {
    @Environment(Session.self) private var session
    var userName: String = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Signed in as \(userName)").font(Theme.Typography.headline)
            Text("Dashboard arrives in the features build.")
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.textSecondary)
            SecondaryButton(title: "Sign out") { Task { await session.signOut() } }
                .frame(maxWidth: 200)
        }
        .padding(Theme.Spacing.lg)
    }
}
