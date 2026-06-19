import SwiftUI
import CaregiverAPI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    let me: Me
    @State private var showAddReceiver = false

    var body: some View {
        Form {
            Section("Team & Receivers") {
                ForEach(me.memberships, id: \.careGroupID) { membership in
                    let groupReceivers = context.receivers.filter { $0.careGroupId == membership.careGroupID }
                    if me.memberships.count > 1 {
                        Text(membership.name)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(groupReceivers, id: \.receiverId) { receiver in
                        NavigationLink(value: Route.receiver(receiver)) {
                            Text(receiver.name)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
                if me.adminGroups.isEmpty == false {
                    Button { showAddReceiver = true } label: {
                        Label("Add receiver", systemImage: "plus")
                    }
                }
            }

            Section("My Account") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Signed in as")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(me.userName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.vertical, Theme.Spacing.xs)

                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .earthBackground()
        .navigationTitle("Settings")
        .sheet(isPresented: $showAddReceiver) {
            AddReceiverView(me: me) {
                Task { await context.load(using: session) }
            }
        }
    }
}
