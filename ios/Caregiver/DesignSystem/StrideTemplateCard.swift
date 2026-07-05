import SwiftUI

/// An add-tracker template picker card (Figma `Stride/Template Card`, set `174:948`),
/// laid in a 2-column grid by the [[add-tracker]] wizard's choose-template step.
/// `.template` = hue-tinted icon square + name + kind badge on a surface card;
/// `.custom` = dashed-border card with a centered accent ⊕ "Custom". Fixed 146pt
/// height so grid rows align. Dumb card — the wizard wraps it in a `Button`.
struct StrideTemplateCard: View {
    enum Style {
        case template(name: String, kind: String, icon: String, hue: Color)
        case custom
    }

    let style: Style

    private enum Metrics {
        static let height: CGFloat = 146
        static let radius: CGFloat = 16
        static let iconSquare: CGFloat = 44
    }

    var body: some View {
        Group {
            switch style {
            case .template(let name, let kind, let icon, let hue):
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(hue.opacity(0.18))
                        .frame(width: Metrics.iconSquare, height: Metrics.iconSquare)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .foregroundStyle(hue)
                        }
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(kind)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(Theme.Colors.surfaceHi) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .fill(Theme.Colors.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                }

            case .custom:
                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Custom")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .stroke(
                            Theme.Colors.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                }
            }
        }
        .frame(height: Metrics.height)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Template grid") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm + 4) {
        StrideTemplateCard(style: .template(
            name: "Blood Pressure", kind: "Measurement", icon: "heart", hue: Theme.Colors.trackerCyan
        ))
        StrideTemplateCard(style: .template(
            name: "Medication", kind: "Scheduled", icon: "pills", hue: Theme.Colors.trackerViolet
        ))
        StrideTemplateCard(style: .template(
            name: "Weight", kind: "Measurement", icon: "scalemass", hue: Theme.Colors.trackerTeal
        ))
        StrideTemplateCard(style: .custom)
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
