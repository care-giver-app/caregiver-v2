import SwiftUI

/// The title + subtitle that opens each Getting in screen and sheet (Figma "Getting
/// in", 349:3180: 22pt semibold over 14pt secondary).
struct AuthHeading: View {
    let title: String
    var subtitle: String?
    var alignment: TextAlignment = .leading

    var body: some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(alignment)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

extension View {
    /// The 13pt accent text link Getting in uses for Forgot password?, the Sign in /
    /// Sign up cross-links, Resend, and the sheets' way back.
    func authLinkStyle() -> some View {
        font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.Colors.accent)
    }

    /// A Getting in banner, if there is one, with the space above it.
    @ViewBuilder func authBanner(_ banner: AuthBanner?, spacing: CGFloat = 12) -> some View {
        VStack(spacing: 0) {
            self
            if let banner {
                StrideAlertBanner(message: banner.message, tone: banner.tone)
                    .padding(.top, spacing)
            }
        }
    }
}

/// The sheet Getting in raises — Confirm code or Reset password — sized to its
/// content (Figma 356:3246 / 357:3305: white, 22pt corners, a grabber).
struct AuthSheetView: View {
    @Bindable var model: AuthModel

    /// What was last shown, so the content does not blank while the sheet animates away.
    @State private var lastShown: AuthSheet?
    @State private var height: CGFloat = 420

    var body: some View {
        Group {
            switch model.sheet ?? lastShown {
            case .confirmCode:
                ConfirmCodeView(model: model)
            case .resetPassword(let step):
                ResetPasswordView(model: model, step: step)
            case nil:
                Color.clear
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 28)
        .padding(.bottom, Theme.Spacing.sm)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.surface)
        .presentationCornerRadius(22)
        .interactiveDismissDisabled(model.isBusy)
        .tint(Theme.Colors.accent)
        .onChange(of: model.sheet, initial: true) { _, sheet in
            if let sheet { lastShown = sheet }
        }
    }
}
