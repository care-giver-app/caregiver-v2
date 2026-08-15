import SwiftUI

struct StrideMemberRow: View {
    enum MemberState {
        case active(name: String, initial: String, isYou: Bool = false)
        case pending(email: String, meta: String, onRevoke: (() -> Void)? = nil)
    }

    let state: MemberState
    let role: String

    private enum Metrics {
        static let avatarSize: CGFloat = 36
        static let radius: CGFloat = 14
    }

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .active(let name, let initial, let isYou):
                avatar(isYou: isYou) {
                    // Space Grotesk in Figma; system stands in (pending-font note in spec).
                    Text(initial)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if isYou {
                      StrideBadge(status: .informational, label: "You")
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                StrideBadge(status: .informational, label: role)

            case .pending(let email, let meta, let onRevoke):
                avatar(isYou: false) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(email)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                HStack(spacing: 10) {
                  StrideBadge(status: .muted, label: role)
                    if let onRevoke {
                        Button(action: onRevoke) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Revoke invite")
                    }
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func avatar(isYou: Bool, @ViewBuilder content: () -> some View) -> some View {
        Circle()
            .fill(Theme.Colors.surfaceHi)
            .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
            .overlay { content() }
            .overlay {
                if isYou {
                    Circle().stroke(Theme.Colors.accent, lineWidth: 1.5)
                }
            }
    }
}

#Preview("Team roster") {
    VStack(spacing: 10) {
        StrideMemberRow(state: .active(name: "Trevor", initial: "T", isYou: true), role: "Admin")
        StrideMemberRow(state: .active(name: "Dana", initial: "D"), role: "Caregiver")
        StrideMemberRow(state: .active(name: "Marcus", initial: "M"), role: "Caregiver")
        StrideMemberRow(
            state: .pending(email: "jordan@email.com", meta: "Invited · expires 7d", onRevoke: {}),
            role: "Caregiver"
        )
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
