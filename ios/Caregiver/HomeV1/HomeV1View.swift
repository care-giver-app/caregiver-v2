import SwiftUI

/// Home on the `/v1` path (PRD "Home"). For now it shows only who Home is about; the
/// sections are still to be built.
struct HomeV1View: View {
    let receiver: ActiveReceiverModel
    let service: HomeService

    var body: some View {
        Group {
            switch receiver.phase {
            case .loading:
                StrideLoadingView()
            case .failed(let error):
                StrideErrorState(message: error.message) { Task { await receiver.retry() } }
            case .noReceivers(let team, let canManage):
                noReceivers(team: team, canManage: canManage)
            case .active(let active):
                header(active)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { if receiver.phase == .loading { await receiver.load() } }
    }

    private func header(_ active: TeamedReceiver) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(active.receiver.name)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(active.team.name)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noReceivers(team: Account.Team, canManage: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(team.name) has no care receivers yet.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            // Add care receiver is a Team-area sheet that isn't built on this path yet.
            Text(canManage ? "Adding a care receiver isn't built here yet." : "An admin adds them.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
@MainActor
private func previewModel(_ byTeam: [String: [TeamReceiver]] = HomeFixtures.receiversByTeam,
                          fail: Bool = false) -> ActiveReceiverModel {
    ActiveReceiverModel(account: HomeFixtures.trevor,
                        service: HomeFixtures.trackersService(receiversByTeam: byTeam, failReceivers: fail),
                        store: .inMemory())
}

#Preview("Eleanor") {
    NavigationStack { HomeV1View(receiver: previewModel(), service: HomeFixtures.service()) }
}

#Preview("No receivers") {
    NavigationStack { HomeV1View(receiver: previewModel([:]), service: HomeFixtures.service()) }
}

#Preview("Failed") {
    NavigationStack { HomeV1View(receiver: previewModel(fail: true), service: HomeFixtures.service()) }
}
#endif
