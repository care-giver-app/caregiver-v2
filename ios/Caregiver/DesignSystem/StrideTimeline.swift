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

    // Aurora node treatment (Figma `Stride/Timeline Node`, 93:144): right-aligned time
    // gutter, top-aligned glowing dot with the rail running down from it, 14/12pt text.
    private func row(_ node: StrideTimelineNode, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Gutter: optional icon over the right-aligned time label
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                if let icon = node.icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(node.iconColor)
                }
                if let time = node.time {
                    Text(time)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 52, alignment: .trailing)

            // Rail: glowing dot at the row's top, line continuing down to the next node
            VStack(spacing: 0) {
                Circle()
                    .fill(node.dotColor)
                    .frame(width: 11, height: 11)
                    .shadow(color: node.dotColor.opacity(0.9), radius: 3)
                if !isLast {
                    Rectangle()
                        .fill(Theme.Colors.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)
            .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let description = node.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            if node.action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { node.action?() }
        .allowsHitTesting(node.action != nil)
    }
}
