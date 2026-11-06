import SwiftUI

/// An invitation waiting for the signed-in caregiver's email, on Join a care team
/// (Figma `Stride/Invitation Row`, 352:3197): the care team, who invited you, and Accept.
struct StrideInvitationRow: View {
    let team: String
    let invitedBy: String
    var isAccepting: Bool = false
    let onAccept: () -> Void

    private enum Metrics {
        static let height: CGFloat = 76
        static let radius: CGFloat = Theme.Radius.card
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(team)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Invited by \(invitedBy)")
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onAccept) {
                ZStack {
                    Text("Accept").opacity(isAccepting ? 0 : 1)
                    if isAccepting { ProgressView().tint(Theme.Colors.accent) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(isAccepting)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: Metrics.height)
        .background {
            RoundedRectangle(cornerRadius: Metrics.radius).fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius).stroke(Theme.Colors.border, lineWidth: 1)
        }
    }
}

#Preview("Waiting + accepting") {
    VStack(spacing: 10) {
        StrideInvitationRow(team: "Delgado Family", invitedBy: "Lucia", onAccept: {})
        StrideInvitationRow(team: "Delgado Family", invitedBy: "Lucia", isAccepting: true, onAccept: {})
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .strideBackground()
}
