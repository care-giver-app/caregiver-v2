import SwiftUI

/// An inline message under a form field (Figma `Stride/Alert Banner`, 352:3196).
/// `.error` for failures, `.info` for neutral reassurance.
struct StrideAlertBanner: View {
    enum Tone { case error, info }

    let message: String
    var tone: Tone = .error

    private enum Metrics {
        static let radius: CGFloat = 10
        static let hPadding: CGFloat = 14
        static let vPadding: CGFloat = 11
    }

    var body: some View {
        Text(message)
            .font(Theme.Typography.subhead)
            .foregroundStyle(tone == .error ? Theme.Colors.alert : Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.hPadding)
            .padding(.vertical, Metrics.vPadding)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(tone == .error ? Color(hex: "f9e0e5") : Color(hex: "d9eaf8"))
            }
    }
}

#Preview("Error + info") {
    VStack(spacing: Theme.Spacing.md) {
        StrideAlertBanner(message: "This invite code is no longer valid")
        StrideAlertBanner(message: "If an account exists for that address, a code is on its way.", tone: .info)
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .strideBackground()
}
