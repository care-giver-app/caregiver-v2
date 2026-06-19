import SwiftUI

struct GlassField: View {
    let placeholder: String
    var icon: String? = nil
    var isSecure: Bool = false
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(width: 20)
            }
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Colors.ink)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md - 2)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.25), .clear],
                            startPoint: .top, endPoint: .center
                        ))
                }
        }
        .shadow(color: Theme.Colors.ink.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct GlassButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .font(Theme.Typography.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md - 2)
            .foregroundStyle(Theme.Colors.ink)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    }
            }
        }
        .shadow(color: Theme.Colors.ink.opacity(0.3), radius: 8, x: 0, y: 4)
        .buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
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
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .fill(Theme.Colors.accent.opacity(0.75))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .center
                            ))
                    }
            }
            .shadow(color: Theme.Colors.ink.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md - 3)
                .foregroundStyle(Theme.Colors.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(Theme.Colors.accent, lineWidth: 1.5)
                )
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
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

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            SecondaryButton(title: "Try again", action: retry)
                .frame(maxWidth: 200)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
