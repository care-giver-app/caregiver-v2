import SwiftUI
import CaregiverAPI

struct LogEventView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let tracker: Components.Schemas.Tracker
    let existing: Components.Schemas.Event?
    let onSaved: () -> Void
    @State private var model: LogEventModel

    init(tracker: Components.Schemas.Tracker, existing: Components.Schemas.Event?, onSaved: @escaping () -> Void) {
        self.tracker = tracker
        self.existing = existing
        self.onSaved = onSaved
        _model = State(initialValue: LogEventModel(tracker: tracker, existing: existing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($model.inputs) { $input in
                        fieldRow($input)
                    }
                }
                Section {
                    DatePicker("When", selection: $model.occurredAt)
                    TextField("Note (optional)", text: $model.note, axis: .vertical)
                }
                if let error = model.formError {
                    Text(error.message).foregroundStyle(Theme.Colors.alert)
                }
            }
            .navigationTitle(existing == nil ? "Log reading" : "Edit reading")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.submit(using: session) { onSaved(); dismiss() } }
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
