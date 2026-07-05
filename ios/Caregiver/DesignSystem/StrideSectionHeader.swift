import SwiftUI

/// A section label row (Figma `Stride/Section Header`): wide-tracked uppercase title
/// on the left, optional accent action ("See all ›") pinned right. The component
/// uppercases the title itself — callers pass natural-case strings. Transparent
/// background; sits directly on the screen background.
struct StrideSectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.96)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionLabel, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionLabel)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
    }
}

#Preview("With and without action") {
    VStack(spacing: Theme.Spacing.lg) {
        StrideSectionHeader(title: "Today")
        StrideSectionHeader(title: "Trackers", actionLabel: "See all", action: {})
        StrideSectionHeader(title: "Care team", actionLabel: "Manage", action: {})
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
