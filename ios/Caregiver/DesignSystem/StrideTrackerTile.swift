import SwiftUI

/// Recency of a tracker's last event — the "recency-as-luminance" signature.
/// Fresh trackers glow, stale ones sit quiet, overdue ones go amber.
enum StrideTrackerRecency {
    case fresh, normal, overdue
}

/// A compact tracker snapshot cell (Figma `Stride/Tracker Tile`): hue dot + name +
/// last-logged line, laid out for the Home snapshot's two-column grid. The dot carries
/// the tracker's identity hue; `.overdue` swaps dot and subtitle to the warning amber
/// (status is a layer over the hue, never a hue itself).
struct StrideTrackerTile: View {
    let name: String
    let subtitle: String
    let hue: Color
    var recency: StrideTrackerRecency = .normal

    private enum Metrics {
        static let dotSize: CGFloat = 10
        static let glowRadius: CGFloat = 3
        static let padding: CGFloat = 12
        static let radius: CGFloat = 14
    }

    private var dotColor: Color {
        recency == .overdue ? Theme.Colors.warning : hue
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: Metrics.dotSize, height: Metrics.dotSize)
                .shadow(
                    color: recency == .fresh ? dotColor.opacity(0.95) : .clear,
                    radius: Metrics.glowRadius
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(recency == .overdue ? Theme.Colors.warning : Theme.Colors.textTertiary)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.padding)
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
    VStack(spacing: Theme.Spacing.sm) {
        StrideTrackerTile(name: "Tracker", subtitle: "2h ago", hue: Theme.Colors.trackerCyan, recency: .fresh)
        StrideTrackerTile(name: "Tracker", subtitle: "2h ago", hue: Theme.Colors.trackerCyan)
        StrideTrackerTile(name: "Tracker", subtitle: "Due", hue: Theme.Colors.trackerCyan, recency: .overdue)
    }
    .frame(width: 168)
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Home snapshot grid") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm + 2) {
        StrideTrackerTile(name: "Blood pressure", subtitle: "2h ago", hue: Theme.Colors.trackerCyan, recency: .fresh)
        StrideTrackerTile(name: "Medication", subtitle: "4h ago", hue: Theme.Colors.trackerViolet)
        StrideTrackerTile(name: "Weight", subtitle: "Yesterday", hue: Theme.Colors.trackerTeal)
        StrideTrackerTile(name: "Pain level", subtitle: "3h ago", hue: Theme.Colors.informational)
        StrideTrackerTile(name: "Meals", subtitle: "Due", hue: Theme.Colors.trackerCyan, recency: .overdue)
        StrideTrackerTile(name: "Hydration", subtitle: "1h ago", hue: Theme.Colors.trackerTeal, recency: .fresh)
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
