import SwiftUI

private struct StrideAuthBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.background, Color(hex: "e4edf9")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            content
        }
    }
}

extension View {
    func strideAuthBackground() -> some View {
        modifier(StrideAuthBackgroundModifier())
    }
}

#Preview {
    Text("Stride")
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideAuthBackground()
}
