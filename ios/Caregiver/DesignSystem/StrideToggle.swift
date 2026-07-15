import SwiftUI

/// Aurora toggle treatment (Figma `Stride/Toggle`, set `156:572`) as a `ToggleStyle`,
/// so call sites keep the system `Toggle`'s semantics (label, tap target, a11y,
/// VoiceOver "on/off") and only the drawing is custom: 46×28 capsule track —
/// `accent` on / `surfaceHi` off — with a snow thumb that slides on a spring.
struct StrideToggleStyle: ToggleStyle {
    private enum Metrics {
        static let trackSize = CGSize(width: 46, height: 28)
        static let thumbSize: CGFloat = 22
        static let thumbInset: CGFloat = 3
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Theme.Colors.accent : Theme.Colors.surfaceHi)
                    .frame(width: Metrics.trackSize.width, height: Metrics.trackSize.height)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Theme.Colors.textPrimary)
                            .frame(width: Metrics.thumbSize, height: Metrics.thumbSize)
                            .padding(Metrics.thumbInset)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == StrideToggleStyle {
    /// `Toggle("Label", isOn: $flag).toggleStyle(.stride)`
    static var stride: StrideToggleStyle { StrideToggleStyle() }
}

#Preview("States") {
    @Previewable @State var on = true
    @Previewable @State var off = false
    VStack(spacing: Theme.Spacing.md) {
        Toggle("Reminders", isOn: $on)
        Toggle("Weekly summary", isOn: $off)
    }
    .toggleStyle(.stride)
    .font(Theme.Typography.body)
    .foregroundStyle(Theme.Colors.textPrimary)
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
