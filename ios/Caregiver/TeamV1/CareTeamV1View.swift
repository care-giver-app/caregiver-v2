import SwiftUI
import UIKit

/// Care team (PRD "Care team"; Figma 450:3560 admin, 450:3660 caregiver, 450:3740 the only
/// admin trying to leave): its caregivers and their roles, readable by everyone; pending
/// invitations with their codes, for admins; its archived care receivers; notification
/// settings; and the way out. `onGone` runs once the caregiver has left or closed it.
struct CareTeamV1View: View {
    let service: TeamService
    let onGone: () -> Void

    @State private var model: CareTeamModel
    @State private var isInviting = false
    @State private var acting: TeamMemberInfo?
    @State private var exit: LeaveTeamModel.Kind?

    init(team: Account.Team, myUserID: String, service: TeamService, model: CareTeamModel? = nil,
         onGone: @escaping () -> Void) {
        self.service = service
        self.onGone = onGone
        _model = State(initialValue: model ?? CareTeamModel(team: team, myUserID: myUserID, service: service))
    }

    var body: some View {
        Group {
            switch model.detail {
            case .loading:
                StrideLoadingView()
            case .failed:
                StrideErrorState(message: TeamText.careTeamFailed) { Task { await model.retry() } }
            case .loaded(let detail):
                content(detail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.visible, for: .navigationBar)
        .strideBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: $isInviting) {
            InviteCaregiverSheet(teamID: model.team.teamID, service: service) { model.invitationCreated($0) }
        }
        .sheet(item: $acting) { member in
            MemberActionsSheet(model: MemberActionsModel(
                member: member, teamID: model.team.teamID, teamName: model.name,
                isOnlyAdmin: member.role == .admin && model.adminCount <= 1, service: service
            )) {
                Task { await model.load() }
            }
        }
        .sheet(item: $exit) { kind in
            LeaveTeamSheet(model: LeaveTeamModel(kind: kind, teamID: model.team.teamID,
                                                 myUserID: model.myUserID, service: service)) { outcome in
                switch outcome {
                case .left: onGone()
                case .onlyAdmin: Task { await model.leaveWasRefused() }
                }
            }
        }
    }

    private func content(_ detail: TeamDetailInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identity(detail)
                    .padding(.bottom, model.leaveRefused ? 20 : 22)
                if model.leaveRefused {
                    onlyAdminCallout.padding(.bottom, 22)
                }
                TeamSectionLabel(TeamText.caregivers)
                roster(detail)
                if model.isAdmin {
                    Button { isInviting = true } label: { AddTrackerActionRow(title: TeamText.inviteCaregiver) }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    pending
                }
                archived
                TeamSectionLabel(TeamText.notifications).padding(.top, 22)
                NavigationLink(value: TeamRoute.notifications(model.team)) {
                    HStack(spacing: 12) {
                        TeamTile(icon: "bell")
                        TeamRowText(title: TeamText.notificationSettings)
                        TeamChevron()
                    }
                    .teamRow()
                    .teamCard()
                }
                .buttonStyle(.plain)
                exitRow.padding(.top, 22)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    private func identity(_ detail: TeamDetailInfo) -> some View {
        HStack(spacing: 14) {
            TeamTile(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.name)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(TeamText.summary(count: detail.members.count, myRole: detail.myRole))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .lineLimit(2)
        }
    }

    /// Figma 450:3763: refused with the reason rather than a greyed-out row (PRD).
    private var onlyAdminCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TeamText.onlyAdminTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.alert)
            Text(TeamText.onlyAdminLine)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.alertTint) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Caregivers

    private func roster(_ detail: TeamDetailInfo) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(detail.members.enumerated()), id: \.element.id) { i, member in
                if i > 0 { TeamRowDivider(inset: 60) }
                memberRow(member)
            }
        }
        .teamCard()
    }

    @ViewBuilder
    private func memberRow(_ member: TeamMemberInfo) -> some View {
        let row = HStack(spacing: 12) {
            TeamMonogram(name: member.name)
            TeamRowText(title: member.name)
            if model.isMe(member) {
                TeamBadge(label: TeamText.you)
            }
            Text(TeamText.roleName(member.role))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
            if model.opens(member) {
                TeamChevron()
            }
        }
        .teamRow()
        if model.opens(member) {
            Button {
                if model.isMe(member) {
                    // Your own row offers leaving and nothing else — closing, for the
                    // last caregiver on the team (PRD).
                    if let kind = model.exitKind() { exit = kind }
                } else {
                    acting = member
                }
            } label: { row }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    // MARK: Pending invitations

    @ViewBuilder
    private var pending: some View {
        switch model.invitations {
        case .loading:
            EmptyView()
        case .failed:
            StrideAlertBanner(message: TeamText.invitationsListFailed).padding(.top, 22)
        case .loaded(let invitations) where invitations.isEmpty:
            EmptyView()
        case .loaded(let invitations):
            TeamSectionLabel(TeamText.pendingInvitations).padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(Array(invitations.enumerated()), id: \.element.id) { i, invitation in
                    if i > 0 { TeamRowDivider(inset: 60) }
                    invitationRow(invitation)
                }
            }
            .teamCard()
        }
    }

    private func invitationRow(_ invitation: TeamInvitationInfo) -> some View {
        HStack(spacing: 12) {
            TeamTile(icon: "envelope")
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.email)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(invitation.code)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textSelection(.enabled)
                Text(TeamText.expires(invitation.expiresAt, now: Date()))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = invitation.code
                model.copied(invitation.code)
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    model.clearCopied(invitation.code)
                }
            } label: {
                Text(model.copiedCode == invitation.code ? TeamText.copied : TeamText.copyCode)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy code for \(invitation.email)")
        }
        .teamRow()
    }

    // MARK: Archived care receivers

    @ViewBuilder
    private var archived: some View {
        switch model.archived {
        case .loading:
            EmptyView()
        case .failed:
            StrideAlertBanner(message: TeamText.archivedFailed).padding(.top, 22)
        case .loaded(let receivers) where receivers.isEmpty:
            EmptyView()
        case .loaded(let receivers):
            TeamSectionLabel(TeamText.archivedReceivers).padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(Array(receivers.enumerated()), id: \.element.id) { i, receiver in
                    if i > 0 { TeamRowDivider(inset: 60) }
                    NavigationLink(value: TeamRoute.careReceiver(receiver)) {
                        HStack(spacing: 12) {
                            TeamMonogram(name: receiver.name)
                            // The contract carries no archive date, so the line says only that.
                            TeamRowText(title: receiver.name, detail: TeamText.archived)
                            TeamChevron()
                        }
                        .teamRow()
                    }
                    .buttonStyle(.plain)
                }
            }
            .teamCard()
        }
    }

    // MARK: The way out

    /// Leave this care team — or, for the last caregiver on it, Close this care team (PRD).
    private var exitRow: some View {
        Button {
            if let kind = model.exitKind() { exit = kind }
        } label: {
            Text(model.isLastCaregiver ? TeamText.close : TeamText.leave)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Colors.alert)
                .teamRow()
                .teamCard()
        }
        .buttonStyle(.plain)
    }
}

extension LeaveTeamModel.Kind: Identifiable {
    var id: Self { self }
}

#if DEBUG
private enum CareTeamPreview {
    @MainActor static func view(_ team: Account.Team, service: TeamService = TeamFixtures.service(),
                                refused: Bool = false) -> some View {
        let model = CareTeamModel(team: team, myUserID: "user-trevor", service: service)
        return NavigationStack {
            CareTeamV1View(team: team, myUserID: "user-trevor", service: service, model: model) {}
                .task { if refused { await model.leaveWasRefused() } }
                .navigationDestination(for: TeamRoute.self) { _ in EmptyView() }
        }
    }
}

#Preview("Admin (450:3560)") {
    CareTeamPreview.view(TeamFixtures.riverside)
}

#Preview("Caregiver (450:3660)") {
    CareTeamPreview.view(TeamFixtures.johnson)
}

#Preview("Only admin tries to leave (450:3740)") {
    CareTeamPreview.view(TeamFixtures.riverside,
                         service: TeamFixtures.service(detail: [TeamFixtures.riverside.teamID: TeamFixtures.riversideOnlyAdmin]),
                         refused: true)
}
#endif
