import SwiftUI

/// Wizard progress dots (Figma `StepDots`, frames 75:2/80:2/81:2): one pill per
/// step, the current step elongated (20×6 capsule) and accent-filled, the rest
/// 6×6 muted dots. Purely visual — step state lives in the consumer.
struct StrideStepDots: View {
    let count: Int
    let current: Int

    private enum Metrics {
        static let spacing: CGFloat = 6
        static let currentWidth: CGFloat = 20
        static let dotSize: CGFloat = 6
        static let mutedOpacity: Double = 0.35
        static let animationDuration: Double = 0.15
    }

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.Colors.accent
                                       : Theme.Colors.textSecondary.opacity(Metrics.mutedOpacity))
                    .frame(width: i == current ? Metrics.currentWidth : Metrics.dotSize, height: Metrics.dotSize)
            }
        }
        .animation(.easeOut(duration: Metrics.animationDuration), value: current)
    }
}

#Preview("Step dots") {
    VStack(spacing: 20) {
        StrideStepDots(count: 3, current: 0)
        StrideStepDots(count: 3, current: 1)
        StrideStepDots(count: 3, current: 2)
    }
    .padding()
    .strideAuroraBackground()
}
