import SwiftUI

/// A person's hue for their monogram (Figma Team page): cyan, teal or violet, chosen from
/// the name so the same person keeps one hue on every screen.
enum TeamHue {
    static func color(for name: String) -> Color {
        let hues = [Theme.Colors.trackerCyan, Theme.Colors.trackerTeal, Theme.Colors.trackerViolet]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return hues[sum % hues.count]
    }
}

/// A person's initial on their hue (Figma "Monogram"): care receivers and caregivers.
struct TeamMonogram: View {
    let name: String
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(TeamHue.color(for: name))
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.41, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textOnAccent)
            }
            .accessibilityHidden(true)
    }
}

/// An icon on a tinted rounded tile (Figma "Tile"): a care team, a pending invitation,
/// notifications. `size` 34 in rows, 56 on Care team's identity, 48 on a confirmation.
struct TeamTile: View {
    var icon: String = "person.2"
    var tint: Color = Theme.Colors.accentTint
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29)
            .fill(tint)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityHidden(true)
    }
}

/// A row's name and the line beneath it.
struct TeamRowText: View {
    let title: String
    var detail: String?
    var weight: Font.Weight = .medium
    var color: Color = Theme.Colors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 16, weight: weight))
                .foregroundStyle(color)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short accent label on a row (Figma "Badge"): the active receiver, your own row.
struct TeamBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background { RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.accentTint) }
    }
}

/// The trailing chevron of a row that leads somewhere.
struct TeamChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

/// The hairline between rows on one card; `inset` from its leading edge.
struct TeamRowDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.border)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

extension View {
    /// One row's padding on a grouped card (Figma: 14 across, 12 down).
    func teamRow() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// The bordered white card a group of rows sits on.
    func teamCard() -> some View {
        modifier(AddTrackerCard())
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A section's label above its card ("YOUR CARE TEAMS"), 8pt above it.
struct TeamSectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.72)
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.bottom, Theme.Spacing.sm)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A confirmation's face (Figma 450:3886): a 48pt tile, the question, what it means,
/// then its buttons. Shared by Leave, Close and A caregiver.
struct TeamConfirmation<Tile: View, Buttons: View>: View {
    let title: String
    let line: String
    var failure: String?
    let isWorking: Bool
    @ViewBuilder let tile: Tile
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tile
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
            Text(line)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let failure {
                StrideAlertBanner(message: failure)
                    .padding(.top, Theme.Spacing.md)
            }
            VStack(spacing: 10) {
                buttons
            }
            .padding(.top, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
        .tint(Theme.Colors.accent)
    }
}

/// A sheet's labeled input (Figma "Input: …"): the label, then the box.
struct TeamLabeledInput<Box: View>: View {
    let label: String
    @ViewBuilder let box: Box

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            box
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
        }
    }
}
