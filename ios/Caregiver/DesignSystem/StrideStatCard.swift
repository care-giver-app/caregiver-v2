import SwiftUI

/// A compact headline-stat card (Figma `Stride/Stat Card`): tracked-uppercase label,
/// big stat value, optional tinted delta line ("↓ 3 vs last"), on a surface card.
/// The Insights detail screen lays several in a stat strip. Delta tint defaults to
/// `success`; pass `warning`/`alert`/`textTertiary` for adverse or neutral deltas —
/// direction arrows travel inside the `delta` string.
struct StrideStatCard: View {
    let label: String
    let value: String
    var delta: String? = nil
    var deltaColor: Color = Theme.Colors.success

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.textTertiary)
            // Figma: Space Grotesk Medium — not bundled; system font stands in
            // (same pending-font decision as Inter, see the spec's tokens section).
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
            if let delta {
                Text(delta)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(deltaColor)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Stat strip") {
    HStack(spacing: Theme.Spacing.sm) {
        StrideStatCard(label: "Latest", value: "128/82", delta: "↓ 3 vs last")
        StrideStatCard(label: "Avg (30d)", value: "131/84")
        StrideStatCard(
            label: "Logs", value: "24",
            delta: "↑ 6 vs prior", deltaColor: Theme.Colors.textTertiary
        )
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
