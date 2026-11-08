import SwiftUI

/// What confirming "Sign out?" does: forget this device's saved sign-in, then sign
/// out. The sheet promises the first part, so it happens here rather than in the
/// screen that raised it.
@MainActor
struct SignOutAction {
    /// Turns Face ID off and removes the saved password. The remembered email
    /// (`savedEmail`) stays, so the next sign in is prefilled.
    var forgetDeviceSignIn: () -> Void = { SignOutAction.forgetOnThisDevice() }
    /// `session.signOut()`, which lands on Landing.
    let signOut: () async -> Void

    func callAsFunction() async {
        forgetDeviceSignIn()
        await signOut()
    }

    static func forgetOnThisDevice() {
        KeychainStore.delete()
        UserDefaults.standard.set(false, forKey: "faceIDEnabled")
    }
}

/// Sign out? — the confirmation sheet (PRD `Sign out?`; Figma 481:3594). Raised
/// from Settings and from Join a care team; Cancel dismisses back to whichever
/// screen raised it.
struct SignOutSheet: View {
    let action: SignOutAction

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false
    @State private var height: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 48, height: 48)
                .background {
                    RoundedRectangle(cornerRadius: 14).fill(Color(hex: "d9eaf8"))
                }
                .accessibilityHidden(true)
                .padding(.bottom, Theme.Spacing.md)

            Text("Sign out?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Spacing.sm)

            Text("Face ID turns off and your password leaves this iPhone. Your email stays filled in for next time.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.Spacing.lg)

            VStack(spacing: 10) {
                StrideButton(title: "Sign out", isLoading: isSigningOut) {
                    guard !isSigningOut else { return }
                    isSigningOut = true
                    Task { await action() }
                }
                StrideButton(title: "Cancel", style: .secondary) { dismiss() }
                    .disabled(isSigningOut)
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
        .interactiveDismissDisabled(isSigningOut)
    }
}

#if DEBUG
#Preview("Sign out?") {
    Color.clear
        .strideBackground()
        .sheet(isPresented: .constant(true)) {
            SignOutSheet(action: SignOutAction(forgetDeviceSignIn: {}, signOut: {}))
        }
}
#endif
