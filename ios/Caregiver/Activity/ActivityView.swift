import SwiftUI

struct ActivityView: View {
    @Environment(ReceiverContext.self) private var context

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            Text("Activity coming soon")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.ink)
            if let receiver = context.activeReceiver {
                Text("Recent events for \(receiver.name) will appear here.")
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .navigationTitle("Activity")
        .earthBackground()
    }
}
