import SwiftUI

/// TEMPORARY. Where a caregiver on at least one care team lands while flag `v1_api`
/// is on. It stands in for Home and Team until those areas are built against `/v1`,
/// and exists only so the Getting in flow has somewhere real to end. Delete it when
/// Home ships.
struct V1PlaceholderView: View {
    let account: Account
    let onSignOut: () async -> Void

    @State private var isSigningOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Signed in to \(account.teams.first?.name ?? "")")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(account.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            StrideButton(title: "Sign out", style: .secondary) {
                guard !isSigningOut else { return }
                isSigningOut = true
                Task { await onSignOut() }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .strideBackground()
    }
}

#if DEBUG
#Preview("Placeholder") {
    V1PlaceholderView(account: GettingInFixtures.trevorOnRiverside, onSignOut: {})
}
#endif
