import SwiftUI

/// Team notification settings (PRD; Figma 450:3901): which kinds of reminder and alert
/// this team sends you, by kind for the whole team. The channels are Settings'.
struct TeamNotificationsV1View: View {
    @State private var model: TeamNotificationsModel

    init(team: Account.Team, service: TeamService, model: TeamNotificationsModel? = nil) {
        _model = State(initialValue: model ?? TeamNotificationsModel(team: team, service: service))
    }

    var body: some View {
        Group {
            switch model.choices {
            case .loading:
                StrideLoadingView()
            case .failed:
                StrideErrorState(message: TeamText.notificationsFailed) { Task { await model.retry() } }
            case .loaded(let choices):
                content(choices)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.visible, for: .navigationBar)
        .strideBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StrideNavTitle(title: TeamText.notificationSettings, subtitle: nil)
            }
        }
        .task { await model.load() }
    }

    private func content(_ choices: TeamNotificationChoices) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.team.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 22)
                if model.saveFailed {
                    StrideAlertBanner(message: TeamText.notificationsSaveFailed).padding(.bottom, 16)
                }
                TeamSectionLabel(TeamText.reminders)
                VStack(spacing: 0) {
                    toggle(TeamText.remindersRow, \.reminders, choices)
                }
                .teamCard()
                TeamSectionLabel(TeamText.alerts).padding(.top, 22)
                VStack(spacing: 0) {
                    toggle(TeamText.rangeRow, \.rangeAlerts, choices)
                    TeamRowDivider(inset: 16)
                    toggle(TeamText.gapRow, \.gapAlerts, choices)
                    TeamRowDivider(inset: 16)
                    toggle(TeamText.unrecordedRow, \.unrecordedAlerts, choices)
                }
                .teamCard()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 32)
        }
    }

    private func toggle(_ label: String, _ kind: WritableKeyPath<TeamNotificationChoices, Bool>,
                        _ choices: TeamNotificationChoices) -> some View {
        Toggle(isOn: Binding(get: { choices[keyPath: kind] },
                             set: { on in Task { await model.set(kind, to: on) } })) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .toggleStyle(.stride)
        .disabled(model.isSaving)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#if DEBUG
#Preview("Team notification settings (450:3901)") {
    NavigationStack {
        TeamNotificationsV1View(team: TeamFixtures.riverside, service: TeamFixtures.service())
    }
}
#endif
