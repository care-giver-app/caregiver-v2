import SwiftUI
import CaregiverAPI

/// Sheet to schedule a new upcoming item for a `scheduled`-kind tracker, opened
/// from that tracker's detail screen (ios/specs/views/schedule.md). Create-only —
/// editing/deleting an existing scheduled item is undesigned (spec Gaps).
struct ScheduleItemFormView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let tracker: Components.Schemas.Tracker
    let onScheduled: () -> Void
    @State private var model: ScheduleItemFormModel

    init(tracker: Components.Schemas.Tracker, onScheduled: @escaping () -> Void) {
        self.tracker = tracker
        self.onScheduled = onScheduled
        _model = State(initialValue: ScheduleItemFormModel(tracker: tracker))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("When", selection: $model.scheduledFor)
                }
                if !model.inputs.isEmpty {
                    Section {
                        ForEach($model.inputs) { $input in
                            fieldRow($input)
                        }
                    }
                }
                Section {
                    TextField("Note (optional)", text: $model.note, axis: .vertical)
                }
                if let error = model.formError {
                    Text(error.message).foregroundStyle(Theme.Colors.alert)
                }
            }
            .navigationTitle("Schedule \(tracker.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.submit(using: session) { onScheduled(); dismiss() } }
                    }.disabled(model.isBusy)
                }
            }
        }
    }

    @ViewBuilder private func fieldRow(_ input: Binding<FieldInput>) -> some View {
        let error = model.fieldErrors[input.wrappedValue.key]
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            switch input.wrappedValue.kind {
            case .number:
                HStack {
                    TextField(input.wrappedValue.label, text: input.textValue).keyboardType(.decimalPad)
                    if let unit = input.wrappedValue.unit { Text(unit).foregroundStyle(Theme.Colors.textSecondary) }
                }
            case .text:
                TextField(input.wrappedValue.label, text: input.textValue)
            case .boolean:
                Toggle(input.wrappedValue.label, isOn: input.boolValue)
            case .enumeration:
                Picker(input.wrappedValue.label, selection: input.textValue) {
                    ForEach(input.wrappedValue.options, id: \.self) { Text($0).tag($0) }
                }
            case .datetime:
                DatePicker(input.wrappedValue.label, selection: input.dateValue)
            }
            if let error { Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.alert) }
        }
    }
}
