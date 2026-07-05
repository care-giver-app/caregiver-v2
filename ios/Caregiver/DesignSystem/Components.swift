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

struct StrideField: View {
    let placeholder: String
    var icon: String? = nil
    var isSecure: Bool = false
    @Binding var text: String

    private enum Metrics {
        static let height: CGFloat = 56
        static let radius: CGFloat = 16
        static let iconSize: CGFloat = 20
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md - 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Metrics.iconSize)
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .allowsHitTesting(false)
                }
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
        }
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: Metrics.height)
        .background {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .stroke(Theme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 2.5, y: 3)
    }
}

#Preview("Buttons + field") {
    @Previewable @State var email = ""
    VStack(spacing: Theme.Spacing.md) {
        StrideField(placeholder: "Email", icon: "envelope", text: $email)
        StrideButton(title: "Continue", action: {})
        StrideButton(title: "Continue", isLoading: true, action: {})
        StrideButton(title: "I already have an account", style: .secondary, action: {})
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

struct StrideLoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StrideEmptyState: View {
    let message: String
    var body: some View {
        Text(message)
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StrideErrorState: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            StrideButton(title: "Try again", style: .secondary, action: retry)
                .frame(maxWidth: 200)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    func strideCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.tertiary.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}
