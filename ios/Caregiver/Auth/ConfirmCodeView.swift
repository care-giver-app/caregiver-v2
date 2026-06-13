import SwiftUI

struct ConfirmCodeView: View {
    @Bindable var model: AuthModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Enter the code").font(Theme.Typography.title)
            Text("We emailed a confirmation code to \(model.email).")
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            TextField("Code", text: $model.code).keyboardType(.numberPad)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Confirm", isLoading: model.isBusy) {
                Task { await model.confirm() }
            }
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
        .padding(Theme.Spacing.lg)
    }
}
