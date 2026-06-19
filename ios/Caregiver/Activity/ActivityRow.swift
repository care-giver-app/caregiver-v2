import SwiftUI
import CaregiverAPI

/// One event in the daily timeline: time · (color dot + tracker name) · value summary.
struct ActivityRow: View {
    let ref: EventRef

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    private var dotColor: Color {
        ref.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(Self.timeFormatter.string(from: ref.event.occurredAt))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(ref.tracker.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Text(DynamicFormBuilder.display(values: ref.event.values, fields: ref.tracker.fields))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
