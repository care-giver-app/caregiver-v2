import SwiftUI

/// A selectable tracker tile (Figma `Stride/Select Tile`): hue dot + name + trailing
/// check ring, for picker grids (the quick-log wizard's "choose tracker" step).
/// Selected swaps the ring for an accent-filled check and thickens the card border
/// to 1.5pt accent. Like `StrideChip`, it's a dumb tile — selection state and
/// single/multi rules live in the consumer.
struct StrideSelectTile: View {
    let name: String
    let hue: Color
    var isSelected: Bool = false
    let action: () -> Void

    private enum Metrics {
        static let dotSize: CGFloat = 10
        static let checkSize: CGFloat = 22
        static let radius: CGFloat = 14
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(hue)
                    .frame(width: Metrics.dotSize, height: Metrics.dotSize)
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                check
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .stroke(
                        isSelected ? Theme.Colors.accent : Theme.Colors.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var check: some View {
        if isSelected {
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: Metrics.checkSize, height: Metrics.checkSize)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.textOnAccent)
                }
        } else {
            Circle()
                .stroke(Theme.Colors.border, lineWidth: 1.5)
                .frame(width: Metrics.checkSize, height: Metrics.checkSize)
        }
    }
}

#Preview("Picker grid") {
    @Previewable @State var selected: Set<String> = ["Blood pressure"]
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm + 2) {
        ForEach(
            [("Blood pressure", Theme.Colors.trackerCyan),
             ("Medication", Theme.Colors.trackerViolet),
             ("Weight", Theme.Colors.trackerTeal),
             ("Pain level", Theme.Colors.informational)],
            id: \.0
        ) { name, hue in
            StrideSelectTile(name: name, hue: hue, isSelected: selected.contains(name)) {
                if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
            }
        }
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
