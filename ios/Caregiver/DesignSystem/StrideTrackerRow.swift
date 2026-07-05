import SwiftUI

/// The Trackers view's full-width list row (Figma `Stride/Tracker Row`): hue rail +
/// name over a "Kind · value" subtitle, with meta text ("2h ago") and a chevron
/// pinned to the trailing edge. The rail carries the
/// tracker's identity hue; `.overdue` swaps it to the warning amber (status is a
/// layer over the hue, never a hue itself). Status text ("Due", "Missed", …) is a
/// `StrideBadge` in the trailing slot, typically in place of `meta`.
struct StrideTrackerRow: View {
    let name: String
    var subtitle: String? = nil
    var meta: String? = nil
    let hue: Color
    var recency: StrideTrackerRecency = .normal
    var badge: StrideBadge? = nil

    private enum Metrics {
        static let railSize = CGSize(width: 4, height: 40)
        static let railRadius: CGFloat = 2
        static let glowRadius: CGFloat = 4
        static let itemSpacing: CGFloat = 14
        static let padding: CGFloat = 14
        static let radius: CGFloat = 16
    }

    private var railColor: Color {
        recency == .overdue ? Theme.Colors.warning : hue
    }

    var body: some View {
        HStack(spacing: Metrics.itemSpacing) {
            RoundedRectangle(cornerRadius: Metrics.railRadius)
                .fill(railColor)
                .frame(width: Metrics.railSize.width, height: Metrics.railSize.height)
                .shadow(
                    color: recency == .fresh ? railColor.opacity(0.9) : .clear,
                    radius: Metrics.glowRadius
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.textTertiary)
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
