import SwiftUI

/// A care-receiver row for the switch/add sheets (Figma `Stride/Receiver Row`, set
/// `166:768`): 40pt hue-tinted monogram avatar + name over an age/detail line, with
/// an accent checkmark when this receiver is the active one. Dumb row — the switch
/// sheet wraps it in a `Button`.
struct StrideReceiverRow: View {
    let name: String
    let detail: String
    let initial: String
    let hue: Color
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(hue.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    // Space Grotesk in Figma; system stands in (pending-font note in spec).
                    Text(initial)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(hue)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                // `detail` (age) is usually absent — receivers rarely carry a DOB
                // (receivers.md). Render name-only when there's nothing to show.
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview("Switch sheet") {
    VStack(spacing: 10) {
        StrideReceiverRow(
            name: "Eleanor", detail: "72 years", initial: "E",
            hue: Theme.Colors.trackerCyan, isActive: true
        )
        StrideReceiverRow(
            name: "Harold", detail: "78 years", initial: "H",
            hue: Theme.Colors.trackerTeal
        )
        StrideReceiverRow(
            name: "Rosa", detail: "69 years", initial: "R",
            hue: Theme.Colors.trackerViolet
        )
        // Name-only (no DOB) — the common case; detail line is hidden.
        StrideReceiverRow(
            name: "Walter", detail: "", initial: "W",
            hue: Theme.Colors.trackerCyan
        )
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
