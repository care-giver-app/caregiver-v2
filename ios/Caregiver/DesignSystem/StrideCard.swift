import SwiftUI

// Pre-Aurora treatment (tertiary-based fill); due for the surface + 1px border
// restyle when its consumers migrate — see ios/specs/design-system.md.
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
