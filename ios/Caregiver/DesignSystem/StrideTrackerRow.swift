import SwiftUI

struct StrideTrackerRow: View {
    let name: String
    var subtitle: String? = nil
    var meta: String? = nil
    let hue: Color
    var recency: StrideTrackerRecency = .normal
    var badge: StrideBadge? = nil
    /// An SF Symbol name. When set, the row leads with the tracker's icon on a tile
    /// of its color (Figma 401:3918) in place of the color rail.
    var icon: String? = nil
    /// A paused tracker: its name and subtitle read muted; its color stays its own.
    var isMuted: Bool = false
    /// A subtitle that names a cause reads Medium in this status color — Home's needs
    /// attention: color/alert for out of range, color/warning otherwise (Figma 436:3226).
    var subtitleColor: Color? = nil

    private enum Metrics {
        static let railSize = CGSize(width: 4, height: 40)
        static let railRadius: CGFloat = 2
        static let itemSpacing: CGFloat = 14
        static let padding: CGFloat = 14
        static let radius: CGFloat = 16
        static let tileSize: CGFloat = 34
        static let tileRadius: CGFloat = 10
    }

    private var railColor: Color {
        recency == .overdue ? Theme.Colors.warning : hue
    }

    var body: some View {
        HStack(spacing: Metrics.itemSpacing) {
            if let icon {
                RoundedRectangle(cornerRadius: Metrics.tileRadius)
                    .fill(hue)
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white)
                    }
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: Metrics.railRadius)
                    .fill(railColor)
                    .frame(width: Metrics.railSize.width, height: Metrics.railSize.height)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(isMuted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(subtitleColor == nil ? Theme.Typography.subhead : .system(size: 13, weight: .medium))
                        .foregroundStyle(subtitleColor ?? (isMuted ? Theme.Colors.muted : Theme.Colors.textTertiary))
                }
            }
            Spacer()
            if let meta {
                Text(meta)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            badge
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .lineLimit(1)
        .padding(Metrics.padding)
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
}

#Preview("States") {
    VStack(spacing: 10) {
        StrideTrackerRow(
            name: "Tracker name", subtitle: "Kind · value", meta: "2h ago",
            hue: Theme.Colors.trackerCyan, recency: .fresh
        )
        StrideTrackerRow(
            name: "Tracker name", subtitle: "Kind · value", meta: "2h ago",
            hue: Theme.Colors.trackerCyan
        )
        StrideTrackerRow(
            name: "Tracker name", subtitle: "Kind · value",
            hue: Theme.Colors.trackerCyan, recency: .overdue,
            badge: StrideBadge(status: .warning, label: "Due")
        )
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Icon tile") {
    VStack(spacing: 8) {
        StrideTrackerRow(name: "Blood pressure", subtitle: "Logged 2h ago",
                         hue: Theme.Colors.trackerCyan, icon: "heart")
        StrideTrackerRow(name: "Medication", subtitle: "Logged 9h ago", hue: Theme.Colors.trackerViolet,
                         badge: StrideBadge(status: .warning, label: "Needs attention"), icon: "pills")
        StrideTrackerRow(name: "Walk", subtitle: "Paused Nov 3", hue: Theme.Colors.trackerTeal,
                         icon: "figure.walk", isMuted: true)
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Trackers list") {
    ScrollView {
        VStack(spacing: 10) {
            StrideTrackerRow(
                name: "Meals", subtitle: "Quick log · no value",
                hue: Theme.Colors.trackerCyan, recency: .overdue,
                badge: StrideBadge(status: .warning, label: "Due")
            )
            StrideTrackerRow(
                name: "Hydration", subtitle: "Count · 4 today", meta: "45m ago",
                hue: Theme.Colors.trackerTeal, recency: .fresh
            )
            StrideTrackerRow(
                name: "Medication", subtitle: "Checklist · Lisinopril 10 mg", meta: "2h ago",
                hue: Theme.Colors.trackerViolet, recency: .fresh
            )
            StrideTrackerRow(
                name: "Mood", subtitle: "Scale · Good", meta: "4h ago",
                hue: Theme.Colors.trackerViolet
            )
            StrideTrackerRow(
                name: "Pain level", subtitle: "Numeric · 2 / 10", meta: "6h ago",
                hue: Theme.Colors.informational
            )
            StrideTrackerRow(
                name: "Sleep", subtitle: "Duration · 7h 20m", meta: "last night",
                hue: Theme.Colors.trackerCyan
            )
            StrideTrackerRow(
                name: "Blood pressure", subtitle: "Numeric · 128 / 82", meta: "yesterday",
                hue: Theme.Colors.trackerCyan
            )
        }
        .padding(Theme.Spacing.md)
    }
    .background { Theme.Colors.background.ignoresSafeArea() }
}
