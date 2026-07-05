import SwiftUI

enum StrideButtonStyle { case primary, secondary }

private struct StridePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct StrideButton: View {
    let title: String
    var style: StrideButtonStyle = .primary
    var isLoading: Bool = false
    let action: () -> Void

    private enum Metrics {
        static let height: CGFloat = 54
        static let radius: CGFloat = 16
    }

    var body: some View {
        switch style {
        case .primary: primaryBody
        case .secondary: secondaryBody
        }
    }

    private var primaryBody: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(Theme.Colors.textOnAccent) }
                else { Text(title).font(Theme.Typography.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.height)
            .foregroundStyle(Theme.Colors.textOnAccent)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(Theme.Colors.accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radius)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.15), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    }
            }
            .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 4.5, y: 4)
        }
        .buttonStyle(StridePressStyle())
        .disabled(isLoading)
    }

    private var secondaryBody: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity, minHeight: Metrics.height)
                .foregroundStyle(Theme.Colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .stroke(Theme.Colors.textSecondary.opacity(0.55), lineWidth: 1.5)
                )
        }
        .buttonStyle(StridePressStyle())
    }
}

#Preview("Styles") {
    VStack(spacing: Theme.Spacing.md) {
        StrideButton(title: "Continue", action: {})
        StrideButton(title: "Continue", isLoading: true, action: {})
        StrideButton(title: "I already have an account", style: .secondary, action: {})
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
