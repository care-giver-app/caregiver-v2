import SwiftUI

enum StrideTrackerRecency: Equatable {
    case fresh, normal, overdue
}

struct StrideTrackerTile: View {
    let name: String
    var subtitle: String? = nil
    let hue: Color
    var recency: StrideTrackerRecency = .normal
    var badge: StrideBadge? = nil

    private enum Metrics {
        static let dotSize: CGFloat = 10
        static let padding: CGFloat = 12
        static let radius: CGFloat = 14
        // Badge height; fixed for the whole line so badged and plain tiles grid-align.
        static let secondLineHeight: CGFloat = 19
    }

    private var dotColor: Color {
        recency == .overdue ? Theme.Colors.warning : hue
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: Metrics.dotSize, height: Metrics.dotSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: 6) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    badge
                }
                .frame(minHeight: Metrics.secondLineHeight)
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
        StrideTrackerTile(
            name: "Tracker", hue: Theme.Colors.trackerCyan, recency: .overdue,
            badge: StrideBadge(status: .warning, label: "Due")
        )
        StrideTrackerTile(
            name: "Tracker", subtitle: "3d ago", hue: Theme.Colors.trackerCyan, recency: .overdue,
            badge: StrideBadge(status: .failure, label: "Missed")
        )
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
        StrideTrackerTile(
            name: "Meals", hue: Theme.Colors.trackerCyan, recency: .overdue,
            badge: StrideBadge(status: .warning, label: "Due")
        )
        StrideTrackerTile(name: "Hydration", subtitle: "1h ago", hue: Theme.Colors.trackerTeal, recency: .fresh)
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
