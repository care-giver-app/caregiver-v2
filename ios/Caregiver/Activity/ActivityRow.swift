import SwiftUI
import CaregiverAPI

/// One step in the daily timeline rail: a day/night icon + time in the gutter, a tracker-colored
/// node on a continuous vertical rail (trimmed at the first/last step), then the tracker name and
/// value summary. Earliest event renders at the top.
struct ActivityRow: View {
    let ref: EventRef
    let isFirst: Bool
    let isLast: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    private var isDaytime: Bool { ActivityDay.isDaytime(ref.event.occurredAt) }

    private var nodeColor: Color {
        ref.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent
    }

    private var railColor: Color { Theme.Colors.ink.opacity(0.15) }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            // Gutter: day/night icon + time
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.fill")
                    .font(.caption)
                    .foregroundStyle(isDaytime ? Theme.Colors.amber : Theme.Colors.textSecondary)
                Text(Self.timeFormatter.string(from: ref.event.occurredAt))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(width: 52)

            // Rail: continuous line with a tracker-colored node; trimmed above first / below last.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : railColor)
                    .frame(width: 2)
                Circle()
                    .fill(nodeColor)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(isLast ? Color.clear : railColor)
                    .frame(width: 2)
            }
            .frame(width: 24)

            // Content: tracker name + value summary
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(ref.tracker.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(DynamicFormBuilder.display(values: ref.event.values, fields: ref.tracker.fields))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
