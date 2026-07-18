import SwiftUI
import CaregiverAPI

/// The pushed "Coming up" look-ahead (ios/specs/views/schedule.md): the active
/// receiver's upcoming scheduled items grouped into "This week" / "Later",
/// soonest first. Reads a `ScheduleModel` already loaded by Home; each row links
/// to its tracker. Reuses `StrideTrackerRow` — hue rail, name, note subtitle, and
/// the relative label in the meta slot.
struct ScheduleView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    let model: ScheduleModel

    var body: some View {
        ScrollView {
            content
        }
        .strideBackground()
        .navigationTitle("Coming up")
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            StrideLoadingView().frame(minHeight: 320)
        case .empty:
            StrideEmptyState(message: "No upcoming items.").frame(minHeight: 320)
        case .error(let message):
            StrideErrorState(message: message) { Task { await reload() } }
                .frame(minHeight: 320)
        case .loaded(let items):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(ScheduleBucket.allCases, id: \.self) { bucket in
                    let group = items.filter { $0.bucket() == bucket }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
                            StrideSectionHeader(title: bucket.title)
                            ForEach(group) { item in
                                NavigationLink(value: Route.tracker(item.tracker)) {
                                    StrideTrackerRow(
                                        name: item.name,
                                        subtitle: item.subtitle,
                                        meta: item.relativeLabel(),
                                        hue: item.hue
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
        }
    }

    private func reload() async {
        guard let id = context.activeReceiver?.receiverId else { return }
        await model.load(receiverID: id, using: session)
    }
}
