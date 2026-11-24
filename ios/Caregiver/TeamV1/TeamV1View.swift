import SwiftUI

/// Every screen pushed on the Team tab's own stack (PRD: Care team, Care receiver and Team
/// notification settings are pushes). One `navigationDestination(for:)` at its root, as
/// `V1Route` does on Home's.
enum TeamRoute: Hashable {
    case careTeam(Account.Team)
    case notifications(Account.Team)
    /// Care receiver — built in the next part of the Team area; a named placeholder until then.
    case careReceiver(TeamReceiver)
}

/// The Team tab on the `/v1` path: Team at the root of its own stack, with the screens it
/// pushes. `onPick` takes a care receiver to their Home, as the active one (PRD "Team").
struct TeamTabV1: View {
    let model: TeamListModel
    let service: TeamService
    /// The care receiver Home is about, marked Active on their row.
    let activeReceiverID: String?
    let onPick: (TeamReceiver) -> Void

    @State private var path: [TeamRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            TeamV1View(model: model, service: service, activeReceiverID: activeReceiverID, onPick: onPick)
                .navigationDestination(for: TeamRoute.self) { route in
                    Group {
                        switch route {
                        case .careTeam(let team):
                            CareTeamV1View(team: team, myUserID: model.account.userID, service: service) {
                                // Left or closed: back to Team, which reads the teams afresh.
                                path = []
                                Task { await model.refreshAccount() }
                            }
                        case .notifications(let team):
                            TeamNotificationsV1View(team: team, service: service)
                        case .careReceiver(let receiver):
                            V1PushedPlaceholder(title: receiver.name, subtitle: "Care receiver",
                                                line: "Care receiver isn't built on this path yet.")
                        }
                    }
                    // Pushed screens don't inherit the stack's inset, so each clears the bar itself.
                    .strideTabBarClearance()
                }
                .strideTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

/// Team (PRD "Team"; Figma 450:3226, 450:3372 pasting a code, 450:3458 no care teams):
/// each care team with its receivers, the invitations waiting, and the ways into another.
struct TeamV1View: View {
    let model: TeamListModel
    let service: TeamService
    let activeReceiverID: String?
    let onPick: (TeamReceiver) -> Void

    @State private var isCreating = false
    @State private var addingTo: Account.Team?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Team")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 20)
                if model.accountFailed {
                    StrideAlertBanner(message: TeamText.teamFailed)
                        .padding(.bottom, 12)
                }
                if model.isEmpty {
                    noTeams.padding(.bottom, 22)
                } else {
                    TeamSectionLabel(TeamText.yourCareTeams)
                    VStack(spacing: 12) {
                        ForEach(model.teams) { rows in
                            teamCard(rows)
                        }
                    }
                    .padding(.bottom, 22)
                }
                invitations
                joinAndCreate
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refreshAccount() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        // Each time the tab appears: a receiver added or archived elsewhere shows here.
        .task { await model.load() }
        .sheet(isPresented: $isCreating) {
            CreateCareTeamSheet(service: service) { team in
                Task { await model.created(team) }
            }
        }
        .sheet(item: $addingTo) { team in
            AddCareReceiverSheet(team: team, service: service) { receiver in
                // Lands on the new receiver's Home, as the active one (PRD).
                onPick(receiver)
                Task { await model.load() }
            }
        }
    }

    // MARK: A care team

    private func teamCard(_ rows: TeamListModel.TeamRows) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: TeamRoute.careTeam(rows.team)) {
                HStack(spacing: 12) {
                    TeamTile()
                    TeamRowText(title: rows.team.name, detail: TeamText.role(rows.team.role), weight: .semibold)
                    TeamChevron()
                }
                .teamRow()
            }
            .buttonStyle(.plain)

            switch rows.receivers {
            case .loading:
                TeamRowDivider()
                ProgressView()
                    .tint(Theme.Colors.accent)
                    .teamRow()
            case .failed:
                TeamRowDivider()
                Text(TeamText.receiversFailed)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.alert)
                    .teamRow()
            case .loaded(let receivers):
                ForEach(receivers) { receiver in
                    TeamRowDivider()
                    receiverRow(receiver)
                }
            }

            if rows.isAdmin {
                TeamRowDivider()
                Button { addingTo = rows.team } label: {
                    HStack(spacing: 12) {
                        TeamTile(icon: "plus")
                        TeamRowText(title: TeamText.addReceiver, color: Theme.Colors.accent)
                    }
                    .teamRow()
                }
                .buttonStyle(.plain)
            }
        }
        .teamCard()
    }

    /// The row picks the receiver; its chevron opens Care receiver (PRD).
    private func receiverRow(_ receiver: TeamReceiver) -> some View {
        HStack(spacing: 12) {
            Button { onPick(receiver) } label: {
                HStack(spacing: 12) {
                    TeamMonogram(name: receiver.name)
                    TeamRowText(title: receiver.name, detail: TeamText.zoneName(receiver.timeZone))
                    if receiver.id == activeReceiverID {
                        TeamBadge(label: TeamText.active)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows their Home")
            NavigationLink(value: TeamRoute.careReceiver(receiver)) {
                TeamChevron().frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(receiver.name)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
    }

    // MARK: No care teams

    /// Figma 450:3458 — the PRD's empty state names no words, so these are the design's.
    private var noTeams: some View {
        VStack(spacing: 8) {
            TeamTile(size: 56).padding(.bottom, 4)
            Text(TeamText.noTeamsTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(TeamText.noTeamsLine)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .teamCard()
    }

    // MARK: Invitations waiting

    @ViewBuilder
    private var invitations: some View {
        switch model.invitations {
        case .loading:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                StrideAlertBanner(message: TeamText.invitationsFailed)
                StrideButton(title: "Try again", style: .compact) {
                    Task { await model.retryInvitations() }
                }
            }
            .padding(.bottom, 22)
        case .loaded(let waiting) where waiting.isEmpty:
            if let error = model.invitationError {
                StrideAlertBanner(message: error).padding(.bottom, 22)
            }
        case .loaded(let waiting):
            VStack(alignment: .leading, spacing: 0) {
                TeamSectionLabel(TeamText.waitingForYou)
                VStack(spacing: 0) {
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { i, invitation in
                        if i > 0 { TeamRowDivider() }
                        invitationRow(invitation)
                    }
                }
                .teamCard()
                if let error = model.invitationError {
                    StrideAlertBanner(message: error).padding(.top, 10)
                }
            }
            .padding(.bottom, 22)
        }
    }

    private func invitationRow(_ invitation: PendingInvitation) -> some View {
        HStack(spacing: 12) {
            TeamTile(tint: Theme.Colors.violetTint)
            TeamRowText(title: invitation.teamName, detail: TeamText.invitedBy(invitation.invitedByName),
                        weight: .semibold)
            Button {
                Task { await model.accept(invitation) }
            } label: {
                ZStack {
                    Text("Accept").opacity(model.acceptingCode == invitation.code ? 0 : 1)
                    if model.acceptingCode == invitation.code {
                        ProgressView().tint(Theme.Colors.textOnAccent)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textOnAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background { RoundedRectangle(cornerRadius: 10).fill(Theme.Colors.accent) }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
        }
        .teamRow()
    }

    // MARK: Paste a code, create a team

    @ViewBuilder
    private var joinAndCreate: some View {
        @Bindable var model = model
        if model.isPasting {
            // Figma 450:3372: the field opens in place, under its own label.
            VStack(alignment: .leading, spacing: 0) {
                TeamSectionLabel(model.isEmpty ? TeamText.pasteCode.uppercased() : TeamText.joinAnother)
                TextField("Invite code", text: $model.code)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .focused($codeFocused)
                    .onSubmit { Task { await model.joinWithCode() } }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(model.codeError == nil ? Theme.Colors.border : Theme.Colors.alert, lineWidth: 1)
                    }
                if let error = model.codeError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.alert)
                        .padding(.top, 6)
                }
                StrideButton(title: "Join", isLoading: model.isJoining) {
                    Task { await model.joinWithCode() }
                }
                .disabled(model.isBusy && !model.isJoining)
                .padding(.top, 10)
            }
            .padding(.bottom, 22)
            .onAppear { codeFocused = true }
        } else {
            Button { model.startPasting() } label: { AddTrackerActionRow(title: TeamText.pasteCode) }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
        }
        Button { isCreating = true } label: { AddTrackerActionRow(title: TeamText.createTeam) }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
    }
}

#if DEBUG
private enum TeamPreview {
    @MainActor static func tab(account: Account = TeamFixtures.trevor,
                               service: TeamService? = nil,
                               pasting: Bool = false) -> some View {
        let service = service ?? TeamFixtures.service(account: account)
        let model = TeamListModel(account: account, service: service)
        if pasting { model.startPasting() }
        return TeamTabV1(model: model, service: service, activeReceiverID: HomeFixtures.eleanor.id) { _ in }
    }
}

#Preview("Team (450:3226)") {
    TeamPreview.tab()
}

#Preview("Pasting a code (450:3372)") {
    TeamPreview.tab(service: TeamFixtures.service(redeem: .noLongerValid), pasting: true)
}

#Preview("No care teams (450:3458)") {
    TeamPreview.tab(account: TeamFixtures.trevorNoTeam,
                    service: TeamFixtures.service(account: TeamFixtures.trevorNoTeam, invitations: []))
}

#Preview("Failed") {
    TeamPreview.tab(service: TeamFixtures.service(fail: true))
}
#endif
