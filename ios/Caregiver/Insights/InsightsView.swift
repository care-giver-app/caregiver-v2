import SwiftUI

struct InsightsView: View {
    @Environment(ReceiverContext.self) private var context

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            Text("Insights coming soon")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let receiver = context.activeReceiver {
                Text("Trends and analytics for \(receiver.name) will appear here.")
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .navigationTitle("Insights")
        .strideBackground()
    }
}
