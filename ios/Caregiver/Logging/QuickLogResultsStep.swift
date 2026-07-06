import SwiftUI

/// Final step of the quick-log wizard (ios/specs/views/logging.md decision 5):
/// shown only when at least one POST in the fan-out failed — full success
/// dismisses the wizard directly, so this title is unconditional.
struct QuickLogResultsStep: View {
    let model: QuickLogWizardModel
    let onRetry: () -> Void
    let onDone: () -> Void

    private enum Metrics {
        static let boxRadius: CGFloat = 14
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Some events didn't save")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(model.results) { result in
                        resultRow(result)
                    }
                }
            }
            StrideButton(title: "Retry failed", isLoading: model.isBusy) { onRetry() }
            StrideButton(title: "Done", style: .secondary) { onDone() }
        }
    }

    private func resultRow(_ result: QuickLogResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(result.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(result.success ? Theme.Colors.success : Theme.Colors.alert)
            }
            if !result.success, let message = result.message {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
    }
}

#Preview("Results step — mixed outcomes") {
    let model = QuickLogWizardModel()
    model.results = [
        QuickLogResult(trackerId: "t-meals", name: "Meals", success: true, message: nil),
        QuickLogResult(trackerId: "t-hydration", name: "Hydration", success: false,
                       message: "That didn't look right."),
        QuickLogResult(trackerId: "t-mood", name: "Mood", success: true, message: nil),
        QuickLogResult(trackerId: "t-pain", name: "Pain level", success: false,
                       message: "Couldn't reach the server. Check your connection."),
    ]
    return QuickLogResultsStep(model: model, onRetry: {}, onDone: {})
        .padding(Theme.Spacing.lg)
        .strideBackground()
}
