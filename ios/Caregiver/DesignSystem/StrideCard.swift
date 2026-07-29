import SwiftUI

extension View {
    func strideCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.Colors.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            }
    }
}
