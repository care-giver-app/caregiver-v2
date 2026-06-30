import SwiftUI

struct ConfirmCodeView: View {
    @Bindable var model: AuthModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Check your email")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("We sent a confirmation code to \(model.email).")
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.lg)

                StrideField(placeholder: "Confirmation code", icon: "number", text: $model.code)
                    .keyboardType(.numberPad)

                if let error = model.error {
                    Text(error.message)
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.alert)
                }

                StrideButton(title: "Confirm", isLoading: model.isBusy) {
                    Task { await model.confirm() }
                }

                Spacer()
            }
        .padding(Theme.Spacing.lg)
        .strideBackground()
        .presentationDetents([.medium])
        .presentationCornerRadius(24)
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            ConfirmCodeView(model: {
                let m = AuthModel()
                m.email = "trevor@example.com"
                return m
            }())
        }
}
