import SwiftUI
import CaregiverAPI

/// The care-receiver switch sheet (receivers.md decision 1): a bottom sheet opened
/// from the Home header chevron. Receivers grouped by care group (active group
/// first), tapping one sets it active; an admin-only "+ Add care receiver" row opens
/// the Aurora add sheet. Detents `[.medium, .large]` (decision 8).
struct ReceiverSwitcherSheet: View {
    @Environment(ReceiverContext.self) private var context
    @Environment(\.dismiss) private var dismiss
    let me: Me

    @State private var showAdd = false

    /// Per-receiver hue (decision 3), assigned by stable order across all receivers
    /// so the same person keeps the same colour (Eleanor cyan · Harold teal · Rosa
    /// violet — see sample-data.md).
    private let hues: [Color] = [
        Theme.Colors.trackerCyan, Theme.Colors.trackerTeal, Theme.Colors.trackerViolet,
    ]

    private var groups: [ReceiverSwitcher.Group] {
        ReceiverSwitcher.groups(
            memberships: me.memberships,
            receivers: context.receivers,
            activeGroupID: context.activeReceiver?.careGroupId
        )
    }

    private var flatReceiverIDs: [String] {
        groups.flatMap { $0.receivers.map(\.receiverId) }
    }

    private var canAdd: Bool { !me.adminGroups.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Care receivers")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)

                ForEach(Array(groups.enumerated()), id: \.element.membership.careGroupID) { _, group in
                    if groups.count > 1 {
                        Text(group.membership.name)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.top, Theme.Spacing.xs)
                    }
                    ForEach(group.receivers, id: \.receiverId) { receiver in
                        Button {
                            context.setActive(receiver)
                            dismiss()
                        } label: {
                            StrideReceiverRow(
                                name: receiver.name,
                                detail: "",
                                initial: String(receiver.name.prefix(1)),
                                hue: hue(for: receiver.receiverId),
                                isActive: receiver.receiverId == context.activeReceiverID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if canAdd {
                    Button { showAdd = true } label: { addRow }
                        .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strideBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showAdd) {
            // On success the add sheet dismisses itself and calls onAdded, which
            // also dismisses this switcher so the user lands on the new receiver.
            AddReceiverSheet(me: me) { dismiss() }
        }
    }

    private func hue(for receiverID: String) -> Color {
        guard let index = flatReceiverIDs.firstIndex(of: receiverID) else {
            return Theme.Colors.accent
        }
        return hues[index % hues.count]
    }

    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 40, height: 40)
                .background { Circle().fill(Theme.Colors.accent.opacity(0.15)) }
            Text("Add care receiver")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
    }
}
