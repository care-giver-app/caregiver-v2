import SwiftUI

/// Reusable rename sheet. `onSave` performs the API call and returns an optional
/// error message (nil = success → the sheet dismisses).
struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var text: String
    let onSave: (String) async -> String?

    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $text)
                if let error { Text(error).foregroundStyle(Theme.Colors.alert) }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isBusy = true; error = nil
                            if let message = await onSave(text.trimmingCharacters(in: .whitespaces)) {
                                error = message
                            } else { dismiss() }
                            isBusy = false
                        }
                    }.disabled(isBusy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
