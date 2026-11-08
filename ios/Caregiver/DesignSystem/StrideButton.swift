import SwiftUI

enum StrideButtonStyle {
    case primary, secondary
    /// A small secondary that hugs its title — an inline retry beside a message
    /// (Figma "Try again", 497:241).
    case compact
}

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
        case .compact: compactBody
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
                                colors: [.white.opacity(0.22), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    }
            }
            .shadow(color: Theme.Colors.accent.opacity(0.22), radius: 3.5, y: 3)
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

    private var compactBody: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(Theme.Colors.accent) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius).fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius).stroke(Theme.Colors.border, lineWidth: 1)
            }
        }
        .buttonStyle(StridePressStyle())
        .disabled(isLoading)
    }
}

#Preview("Styles") {
    VStack(spacing: Theme.Spacing.md) {
        StrideButton(title: "Continue", action: {})
        StrideButton(title: "Continue", isLoading: true, action: {})
        StrideButton(title: "I already have an account", style: .secondary, action: {})
        StrideButton(title: "Try again", style: .compact, action: {})
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
