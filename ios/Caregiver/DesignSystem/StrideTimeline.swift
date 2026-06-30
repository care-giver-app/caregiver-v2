import SwiftUI

struct StrideTimelineNode: Identifiable {
    var id = UUID()
    var icon: String? = nil
    var iconColor: Color
    var time: String? = nil
    var title: String
    var description: String? = nil
    var dotColor: Color
    var action: (() -> Void)? = nil

    init(
        icon: String? = nil,
        iconColor: Color = Theme.Colors.textSecondary,
        time: String? = nil,
        title: String,
        description: String? = nil,
        dotColor: Color = Theme.Colors.accent,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.time = time
        self.title = title
        self.description = description
        self.dotColor = dotColor
        self.action = action
    }
}

struct StrideTimeline: View {
    let nodes: [StrideTimelineNode]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                row(node, isFirst: index == 0, isLast: index == nodes.count - 1)
            }
        }
    }

    private func row(_ node: StrideTimelineNode, isFirst: Bool, isLast: Bool) -> some View {
        let railColor = Theme.Colors.textTertiary
        return HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            // Gutter: optional icon + time label
            VStack(spacing: Theme.Spacing.xs) {
                if let icon = node.icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(node.iconColor)
                }
                if let time = node.time {
                    Text(time)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 70)

            // Rail: continuous line with a colored dot; top/bottom lines trimmed at endpoints
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : railColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(node.dotColor)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(isLast ? Color.clear : railColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(node.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let description = node.description {
                    Text(description)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if node.action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture { node.action?() }
        .allowsHitTesting(node.action != nil)
    }
}
