import SwiftUI

struct StrideDialogAction: Identifiable {
    var id = UUID()
    var title: String
    var style: StrideButtonStyle = .primary
    var action: () -> Void

    init(title: String, style: StrideButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }
}

struct StrideDialog: View {
    var icon: String? = nil
    var title: String
    var message: String? = nil
    var actions: [StrideDialogAction]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: Theme.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .font(Theme.Typography.subhead)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(Theme.Spacing.lg)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(actions) { item in
                        StrideButton(title: item.title, style: item.style) {
                            item.action()
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .shadow(color: Theme.Colors.ink.opacity(0.15), radius: 24, x: 0, y: 8)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 320)
        }
    }
}

extension View {
    func strideDialog<V: View>(isPresented: Binding<Bool>, @ViewBuilder dialog: () -> V) -> some View {
        overlay {
            if isPresented.wrappedValue {
                dialog()
            }
        }
    }
}
