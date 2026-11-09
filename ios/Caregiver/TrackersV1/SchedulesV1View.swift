import SwiftUI

/// Schedules — one tracker's schedules, read by anyone on the team (PRD
/// "Schedules"; Figma 428:4103). Nothing here edits; Edit arrives with PR 4.
struct SchedulesV1View: View {
    let trackerID: String
    let trackerName: String
    /// Whose tracker it is; `canManage` says whether Edit is offered.
    let receiver: TeamReceiver
    let service: TrackersService

    @State private var model: SchedulesV1Model?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .strideBackground()
        .toolbar(.visible, for: .navigationBar)
        .strideBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StrideNavTitle(title: "Schedules", subtitle: trackerName)
            }
        }
        .tint(Theme.Colors.accent)
        .task {
            if model == nil {
                let model = SchedulesV1Model(trackerID: trackerID, service: service)
                self.model = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: SchedulesV1Model) -> some View {
        switch model.phase {
        case .loading:
            StrideLoadingView()
        case .failed:
            StrideErrorState(message: "Couldn't load the schedules.") {
                Task { await model.retry() }
            }
        case .loaded(let schedules) where schedules.isEmpty:
            StrideEmptyState(message: "This tracker has no schedules.")
        case .loaded(let schedules):
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    if model.refreshFailed {
                        StrideAlertBanner(message: "Couldn't refresh the schedules.")
                    }
                    ForEach(schedules) { schedule in
                        row(schedule)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .refreshable { await model.load() }
        }
    }

    /// Figma 428:4179: its name; its days, how often, and time; whether it alerts.
    private func row(_ schedule: TrackerScheduleItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(schedule.name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Group {
                Text(TrackerText.scheduleLine(schedule))
                if schedule.unrecordedAlert {
                    Text(TrackerText.alertsIfUnrecorded)
                }
            }
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Medication") {
    NavigationStack {
        SchedulesV1View(trackerID: "medication", trackerName: "Medication",
                        receiver: TrackersFixtures.eleanor, service: TrackersFixtures.service())
    }
}
#endif
