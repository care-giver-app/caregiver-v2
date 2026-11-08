import SwiftUI

/// Offer Face ID — raised over Home the first time a caregiver reaches it on a
/// device that supports it (PRD "Getting into the app"; Figma 359:3390). Reads
/// "Touch ID" on a device that has that instead.
struct OfferFaceIDSheet: View {
    var biometryName: String = BiometricAuth.biometryName
    var onEnable: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 320

    /// Figma's "with a glance" is Face ID's; Touch ID is a touch.
    private var gesture: String { biometryName == "Face ID" ? "a glance" : "a touch" }

    var body: some View {
        VStack(spacing: 0) {
            AuthHeading(title: "Use \(biometryName) to sign in?", alignment: .center)
                .padding(.bottom, Theme.Spacing.sm)
            Text("We'll keep your credentials in this device's keychain so you can sign back in with \(gesture). You can turn it off in Settings at any time.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.Spacing.lg)
            StrideButton(title: "Enable") {
                onEnable()
                dismiss()
            }
            .padding(.bottom, 12)
            StrideButton(title: "Not now", style: .secondary) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 28)
        .padding(.bottom, Theme.Spacing.sm)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.surface)
        .presentationCornerRadius(22)
    }
}

#Preview("Face ID") {
    Color.clear
        .strideBackground()
        .sheet(isPresented: .constant(true)) {
            OfferFaceIDSheet(biometryName: "Face ID", onEnable: {})
        }
}

#Preview("Touch ID") {
    Color.clear
        .strideBackground()
        .sheet(isPresented: .constant(true)) {
            OfferFaceIDSheet(biometryName: "Touch ID", onEnable: {})
        }
}
