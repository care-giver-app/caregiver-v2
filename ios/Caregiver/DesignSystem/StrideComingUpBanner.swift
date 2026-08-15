import SwiftUI

struct StrideComingUpBanner: View {
    let title: String
    let relativeLabel: String
    var action: () -> Void

    private enum Metrics {
        static let radius: CGFloat = 14
        static let padding: CGFloat = 14
        static let spacing: CGFloat = 10
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.spacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.informational)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Metrics.spacing)
                Text(relativeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.informational)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coming up: \(title), \(relativeLabel)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Coming up banner") {
    VStack(spacing: Theme.Spacing.md) {
        StrideComingUpBanner(title: "Cardiology check-up", relativeLabel: "in 9 days", action: {})
        StrideComingUpBanner(title: "Physical therapy", relativeLabel: "Tomorrow", action: {})
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
