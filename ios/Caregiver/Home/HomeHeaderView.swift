import SwiftUI
import CaregiverAPI

/// The Home receiver-switcher header (Figma `54:4`): monogram + receiver name +
/// care-group subtitle + caregiver face-pile. Switching keeps the interim `Menu`
/// (home.md decision 5 — the designed switch sheet is a later pass).
struct HomeHeaderView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    let me: Me

    @State private var members: [Components.Schemas.Member] = []
    @State private var showSwitcher = false

    private var activeTeamName: String? {
        guard let groupID = context.activeReceiver?.careGroupId else { return nil }
        return me.teamName(forCareGroup: groupID)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            monogram
            VStack(alignment: .leading, spacing: 2) {
                switcherTrigger
                if let team = activeTeamName {
                    Text(team)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            facePile
        }
        .task(id: context.activeReceiver?.careGroupId) { await loadMembers() }
        .sheet(isPresented: $showSwitcher) {
            ReceiverSwitcherSheet(me: me)
        }
    }

    private var monogram: some View {
        Text(String(context.activeReceiver?.name.prefix(1) ?? "?"))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: 44, height: 44)
            .background { Circle().fill(Theme.Colors.accent.opacity(0.16)) }
            .overlay { Circle().stroke(Theme.Colors.accent.opacity(0.4), lineWidth: 1) }
    }

    private var facePile: some View {
        HStack(spacing: -8) {
            ForEach(members.prefix(4), id: \.userId) { member in
                Text(String(member.name.prefix(1)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 28, height: 28)
                    .background { Circle().fill(Theme.Colors.surfaceHi) }
                    .overlay { Circle().stroke(Theme.Colors.background, lineWidth: 2) }
            }
        }
        .accessibilityLabel("Care team: \(members.map(\.name).joined(separator: ", "))")
    }

    private func loadMembers() async {
        guard session.client != nil else {
            members = []
            return
        }
        guard let groupID = context.activeReceiver?.careGroupId else {
            members = []
            return
        }
        // Interim direct fetch — PR #26's MembersStore replaces this when it merges.
        members = (try? await session.api
            .listMembers(path: .init(careGroupId: groupID))
            .ok.body.json) ?? []
    }

    // MARK: Receiver switcher
    //
    // The chevron opens the `ReceiverSwitcherSheet` (receivers.md decision 1) — the
    // grouping/active-first ordering and the admin "+ Add care receiver" row now live
    // in that sheet. Shown as plain text only when there's nothing to switch to and
    // nothing to add.

    @ViewBuilder private var switcherTrigger: some View {
        let canAddReceiver = !me.adminGroups.isEmpty
        if context.receivers.count <= 1 && !canAddReceiver {
            Text(context.activeReceiver?.name ?? "")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
        } else {
            Button {
                showSwitcher = true
            } label: {
                HStack(spacing: 4) {
                    Text(context.activeReceiver?.name ?? "")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    let session = Session(bootstrap: { throw Session.NotSignedIn() }, signOutHandler: {})
    let context = ReceiverContext()
    context.receivers = [
        Components.Schemas.Receiver(
            receiverId: "eleanor", careGroupId: "riverside", name: "Eleanor",
            createdBy: "trevor", createdAt: Date(), archived: false
        )
    ]
    context.setActive(context.receivers[0])
    let me = Me(
        userName: "Trevor",
        memberships: [Me.Membership(careGroupID: "riverside", name: "The Riverside Group", role: "admin")]
    )
    return HomeHeaderView(me: me)
        .padding()
        .strideBackground()
        .environment(session)
        .environment(context)
}
