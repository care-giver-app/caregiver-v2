import SwiftUI

/// The Aurora screen substrate (Figma auth frames `29:4`/`18:3`/…): a vertical
/// `#050b2e → #0a1640` night gradient with two soft aurora glows bleeding in
/// from the top — cyan top-leading, violet upper-trailing. Figma draws the
/// glows as pre-blurred ellipse images; here they're blurred ellipses so no
/// raster asset ships.
private struct StrideAuroraBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.background, Color(hex: "0a1640")],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(Theme.Colors.accent.opacity(0.22))
                    .frame(width: 560, height: 300)
                    .blur(radius: 70)
                    .offset(x: -60, y: 40)
            }
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(Theme.Colors.trackerViolet.opacity(0.16))
                    .frame(width: 420, height: 220)
                    .blur(radius: 60)
                    .offset(x: 120, y: 120)
            }
            .ignoresSafeArea()
            content
        }
    }
}

extension View {
    func strideAuroraBackground() -> some View {
        modifier(StrideAuroraBackgroundModifier())
    }
}

#Preview {
    Text("Aurora")
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideAuroraBackground()
}
