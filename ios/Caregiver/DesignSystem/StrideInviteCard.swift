import SwiftUI

/// The pending-invite share card (Figma `Stride/Invite Card`): tracked "INVITE CODE"
/// label, big tracked code beside an expiry pill, and a primary share button —
/// on a raised `surfaceHi` card with an accent border and soft cyan glow (the one
/// card in the system that glows; it's the artifact being handed to someone).
/// Token-first invites: the code/link is the credential, no outbound email.
struct StrideInviteCard: View {
    let code: String
    let expiry: String
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INVITE CODE")
                .font(.system(size: 12, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.textTertiary)
            HStack {
                // Space Grotesk in Figma; system stands in (pending-font note in spec).
                Text(code)
                    .font(.system(size: 26, weight: .medium))
                    .tracking(2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(expiry)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background { Capsule().fill(Theme.Colors.surface) }
            }
            StrideButton(title: "Share link", style: .primary, action: onShare)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.surfaceHi)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.Colors.accent, lineWidth: 1)
        }
        .shadow(color: Theme.Colors.accent.opacity(0.2), radius: 12)
    }
}

#Preview("Invite card") {
    StrideInviteCard(code: "7K2P-9QX4", expiry: "expires 7d", onShare: {})
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.Colors.background.ignoresSafeArea() }
}
