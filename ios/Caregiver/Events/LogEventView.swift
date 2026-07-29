import SwiftUI
import CaregiverAPI

/// Aurora "log/edit reading" sheet — presented from `EventDetailView`'s edit
/// flow (and quick-log's single-tracker path). Mirrors the field rendering used
/// by `Logging/QuickLogDetailStep.swift` (enum tiles / number+unit / text / bool /
/// datetime) so both entry points look the same.
struct LogEventView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let tracker: Components.Schemas.Tracker
    let existing: Components.Schemas.Event?
    let onSaved: () -> Void
    @State private var model: LogEventModel

    private enum Metrics {
        static let closeButton: CGFloat = 32
    }

    init(tracker: Components.Schemas.Tracker, existing: Components.Schemas.Event?, onSaved: @escaping () -> Void) {
        self.tracker = tracker
        self.existing = existing
        self.onSaved = onSaved
        _model = State(initialValue: LogEventModel(tracker: tracker, existing: existing))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach($model.inputs) { $input in
                        DynamicFieldRow(input: $input, error: model.fieldErrors[input.key])
                    }
                    whenRow
                    StrideField(placeholder: "Note (optional)", text: $model.note)
                }
            }
            if let error = model.formError {
                Text(error.message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.alert)
            }
            StrideButton(title: "Save", isLoading: model.isBusy) {
                Task { if await model.submit(using: session) { onSaved(); dismiss() } }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .strideBackground()
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isBusy)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: Metrics.closeButton, height: Metrics.closeButton)
                    .background { Circle().fill(Theme.Colors.surface) }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .opacity(model.isBusy ? 0.5 : 1)
            Spacer()
            Text(existing == nil ? "Log reading" : "Edit reading")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Color.clear.frame(width: Metrics.closeButton, height: Metrics.closeButton)
        }
    }

    private var whenRow: some View {
        StrideDatePicker(label: "When", selection: $model.occurredAt)
    }
}
