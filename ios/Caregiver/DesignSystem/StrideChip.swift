import SwiftUI

/// A self-sizing filter/choice pill (Figma `Stride/Chip`): capsule with a 13pt label
/// that hugs its width. Selected = accent-tinted fill + accent border/text; default =
/// surface + border. A dumb pill — "exactly one selected" lives in the consumer row
/// (Trackers filters, invite-sheet role picker), not here.
struct StrideChip: View {
    let label: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(
                        isSelected ? Theme.Colors.accent.opacity(0.16) : Theme.Colors.surface
                    )
                }
                .overlay {
                    Capsule().stroke(
                        isSelected ? Theme.Colors.accent : Theme.Colors.border,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Types") {
    HStack(spacing: Theme.Spacing.sm) {
        StrideChip(label: "Filter", action: {})
        StrideChip(label: "Filter", isSelected: true, action: {})
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Consumers") {
    @Previewable @State var filter = "All"
    @Previewable @State var role = "Caregiver"
    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
        // Trackers filter row
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(["All", "Needs attention", "Archived"], id: \.self) { name in
                StrideChip(label: name, isSelected: filter == name) { filter = name }
            }
        }
        // Invite-sheet role picker
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(["Caregiver", "Admin"], id: \.self) { name in
                StrideChip(label: name, isSelected: role == name) { role = name }
            }
        }
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
