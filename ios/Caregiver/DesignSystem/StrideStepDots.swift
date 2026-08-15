import SwiftUI

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
    .strideAuthBackground()
}
