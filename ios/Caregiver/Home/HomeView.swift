import SwiftUI
import CaregiverAPI

private struct HomeTaskID: Equatable {
    let receiverID: String?
    let contextReady: Bool
}

// MARK: - Model

@MainActor
@Observable
final class HomeModel {
    enum State: Equatable {
        case loading
        case loaded([Components.Schemas.Tracker])
        case empty
        case error(String)
    }

    var state: State

    init(state: State = .loading) { self.state = state }

    func load(receiverID: String, using session: Session) async {
        state = .loading
        do {
            let response = try await session.api.listTrackers(path: .init(receiverId: receiverID))
            let trackers = try response.ok.body.json.filter { !$0.archived }
            state = trackers.isEmpty ? .empty : .loaded(trackers)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }
}

// MARK: - View

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    let me: Me

    @State private var model: HomeModel
    @State private var logTracker: Components.Schemas.Tracker?
    @State private var showAddReceiver = false
    @State private var showAddTracker = false

    private var activeTeamName: String? {
        guard let groupID = context.activeReceiver?.careGroupId else { return nil }
        return me.teamName(forCareGroup: groupID)
    }

    private var isAdminForActive: Bool {
        guard let groupID = context.activeReceiver?.careGroupId else { return false }
        return me.isAdmin(inCareGroup: groupID)
    }

    init(me: Me) {
        self.me = me
        _model = State(initialValue: HomeModel())
    }

    init(me: Me, model: HomeModel) {
        self.me = me
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingView()
            case .empty:
                emptyState
            case .error(let message):
                ErrorStateView(message: message) { Task { await reload() } }
            case .loaded(let trackers):
                trackerList(trackers)
            }
        }
        .earthBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    receiverSwitcher
                    if let team = activeTeamName {
                        Text(team)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { logTracker != nil },
            set: { if !$0 { logTracker = nil } }
        )) {
            if let tracker = logTracker {
                LogEventView(tracker: tracker, existing: nil) {
                    Task { await reload() }
                }
            }
        }
        .sheet(isPresented: $showAddReceiver) {
            AddReceiverView(me: me) {
                Task { await context.load(using: session) }
            }
        }
        .sheet(isPresented: $showAddTracker) {
            if let receiver = context.activeReceiver {
                TemplatePickerView(receiverId: receiver.receiverId) {
                    Task { await reload() }
                }
            }
        }
        .task(id: HomeTaskID(receiverID: context.activeReceiver?.receiverId, contextReady: context.isLoaded)) {
            await reload()
        }
    }

    private func reload() async {
        guard let id = context.activeReceiver?.receiverId else {
            if context.isLoaded { model.state = .empty }
            return
        }
        await model.load(receiverID: id, using: session)
    }

    // MARK: Empty state

    @ViewBuilder private var emptyState: some View {
        if isAdminForActive, context.activeReceiver != nil {
            VStack(spacing: Theme.Spacing.md) {
                EmptyStateView(message: "No trackers yet.")
                PrimaryButton(title: "Add tracker") {
                    showAddTracker = true
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        } else {
            EmptyStateView(message: "No trackers yet.")
        }
    }

    // MARK: Receiver switcher

    @ViewBuilder private var receiverSwitcher: some View {
        let canAddReceiver = !me.adminGroups.isEmpty
        if context.receivers.count <= 1 && !canAddReceiver {
            Text(context.activeReceiver?.name ?? "")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.ink)
        } else {
            Menu {
                let activeGroupID = context.activeReceiver?.careGroupId
                // Active team first (stable), then other teams. Pre-filter to groups
                // that actually have receivers so dividers only separate rendered
                // sections (never appear at the top).
                let visibleGroups: [(membership: Me.Membership, receivers: [Components.Schemas.Receiver])] =
                    me.memberships
                        .sorted { lhs, rhs in
                            let lhsActive = lhs.careGroupID == activeGroupID
                            let rhsActive = rhs.careGroupID == activeGroupID
                            if lhsActive != rhsActive { return lhsActive }
                            return false
                        }
                        .compactMap { membership in
                            let receivers = context.receivers.filter { $0.careGroupId == membership.careGroupID }
                            return receivers.isEmpty ? nil : (membership, receivers)
                        }
                ForEach(Array(visibleGroups.enumerated()), id: \.element.membership.careGroupID) { index, group in
                    if index > 0 { Divider() }
                    Section(group.membership.name) {
                        ForEach(group.receivers, id: \.receiverId) { receiver in
                            Button {
                                context.setActive(receiver)
                            } label: {
                                if receiver.receiverId == context.activeReceiverID {
                                    Label(receiver.name, systemImage: "checkmark")
                                } else {
                                    Text(receiver.name)
                                }
                            }
                        }
                    }
                }
                if canAddReceiver {
                    Divider()
                    Button {
                        showAddReceiver = true
                    } label: {
                        Label("Add receiver", systemImage: "plus")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(context.activeReceiver?.name ?? "")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.ink)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                }
            }
        }
    }

    // MARK: Tracker list

    private func trackerList(_ trackers: [Components.Schemas.Tracker]) -> some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(trackers, id: \.trackerId) { tracker in
                    TrackerCard(tracker: tracker) {
                        logTracker = tracker
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .refreshable { await reload() }
    }
}

// MARK: - Tracker card

struct TrackerCard: View {
    let tracker: Components.Schemas.Tracker
    let onLog: () -> Void

    var trackerColor: Color {
        tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent
    }

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink(value: Route.tracker(tracker)) {
                HStack(spacing: Theme.Spacing.md) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(trackerColor)
                        .frame(width: 4, height: 40)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(tracker.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.ink)
                        Text(tracker.kind.rawValue.capitalized)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.leading, Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Theme.Colors.ink.opacity(0.08))
                .frame(width: 1, height: 40)

            Button(action: onLog) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.25), .clear],
                            startPoint: .top, endPoint: .center
                        ))
                }
        }
        .shadow(color: Theme.Colors.ink.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
