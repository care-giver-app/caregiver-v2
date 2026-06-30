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

    var body: some View {
        switch style {
        case .primary: primaryBody
        case .secondary: secondaryBody
        }
    }

    private var primaryBody: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else { Text(title).font(Theme.Typography.headline) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md - 2)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(Theme.Colors.accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.15), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    }
            }
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(StridePressStyle())
        .disabled(isLoading)
    }

    private var secondaryBody: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md - 3)
                .foregroundStyle(Theme.Colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(Theme.Colors.textPrimary, lineWidth: 1.5)
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

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 20)
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.white.opacity(0.55))
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
        .padding(.vertical, Theme.Spacing.md - 2)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(.white.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .stroke(.white.opacity(0.45), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
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
