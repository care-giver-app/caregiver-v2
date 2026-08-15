import SwiftUI

/// The CareToSher brand mark (Figma `Stride/Brand`): the logo alone — the light
/// "ice chip" plaque from the Aurora era is retired now that the app substrate
/// itself is light (see ios/specs/design-system.md).
struct StrideBrand: View {
    private enum Metrics {
        static let logoWidth: CGFloat = 220
        static let logoHeight: CGFloat = 140
    }

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: Metrics.logoWidth, height: Metrics.logoHeight)
            .accessibilityLabel("CareToSher")
    }
}

#Preview {
    StrideBrand()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.Colors.background.ignoresSafeArea() }
}
