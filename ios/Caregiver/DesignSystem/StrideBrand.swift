import SwiftUI

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
