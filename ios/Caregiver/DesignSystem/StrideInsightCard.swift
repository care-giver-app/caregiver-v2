import SwiftUI

/// A filled mini area-sparkline with an endpoint dot (the `spark` slot of the
/// Insight Card; no axes or labels). Values are normalized to the view's bounds —
/// pass raw numbers. Drawn with `Path`, not Swift Charts: a chrome-less mini
/// doesn't need axes, and this keeps it cheap inside scrolling card lists.
struct StrideSparkline: View {
    let values: [Double]
    let hue: Color

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            if let last = points.last {
                area(through: points, in: geo.size)
                    .fill(hue.opacity(0.85))
                Circle()
                    .fill(hue)
                    .frame(width: 6, height: 6)
                    .position(last)
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1,
              let min = values.min(), let max = values.max() else { return [] }
        let span = max - min
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let unit = span == 0 ? 0.5 : (value - min) / span
            // Keep a little headroom so the endpoint dot isn't clipped.
            let y = size.height * (1 - 0.8 * unit) - 3
            return CGPoint(x: x, y: y)
        }
    }

    private func area(through points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            path.closeSubpath()
        }
    }
}

/// The Insights overview card, one per tracker (Figma `Stride/Insight Card`):
/// hue dot + name, a big count with its caption on the same baseline, a "latest"
/// line, and a 100×44 hue sparkline pinned right. Dumb card — the consumer wraps
/// it for the tap-to-drill-down.
struct StrideInsightCard: View {
    let name: String
    let hue: Color
    let count: String
    var countCaption: String = "logs this month"
    var latest: String? = nil
    var sparkline: [Double] = []

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hue)
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Space Grotesk in Figma; system stands in (pending-font note in spec).
                    Text(count)
                        .font(.system(size: 22, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(countCaption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                if let latest {
                    Text(latest)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            if sparkline.count > 1 {
                StrideSparkline(values: sparkline, hue: hue)
                    .frame(width: 100, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Insights overview") {
    VStack(spacing: 10) {
        StrideInsightCard(
            name: "Blood Pressure", hue: Theme.Colors.trackerCyan, count: "12",
            latest: "last 128/82 mmHg", sparkline: [131, 128, 133, 129, 127, 130, 126, 128]
        )
        StrideInsightCard(
            name: "Medication", hue: Theme.Colors.trackerViolet, count: "28",
            latest: "last Lisinopril 10 mg · taken", sparkline: [1, 1, 0, 1, 1, 1, 1, 1]
        )
        StrideInsightCard(
            name: "Weight", hue: Theme.Colors.trackerTeal, count: "4",
            latest: "last 154.2 lb", sparkline: [156.5, 155.8, 154.9, 154.2]
        )
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
