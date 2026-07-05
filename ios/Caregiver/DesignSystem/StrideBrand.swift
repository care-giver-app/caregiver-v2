import SwiftUI

/// The CareToSher brand plaque (Figma `Stride/Brand`): the dark logo on a light
/// "ice chip" slab so the mark stays legible on the Aurora navy background.
/// Fixed-size — every auth screen top-anchors the same instance.
struct StrideBrand: View {
    private enum Metrics {
        static let logoWidth: CGFloat = 200
        static let logoHeight: CGFloat = 82
        static let radius: CGFloat = 20
    }

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: Metrics.logoWidth, height: Metrics.logoHeight)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md - 4)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(Color(hex: "f1f6ff").opacity(0.96))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .stroke(.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 11)
            .shadow(color: Color(hex: "000d26").opacity(0.45), radius: 12, y: 8)
            .accessibilityLabel("CareToSher")
    }
}

#Preview {
    StrideBrand()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.Colors.background.ignoresSafeArea() }
}
