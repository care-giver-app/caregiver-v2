import SwiftUI

@MainActor
@Observable
final class AddReceiverModel {
    var name = ""
    var selectedGroupID = ""
    var isBusy = false
    var error: AppError?

    func create(using session: Session, onDone: () -> Void) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = AppError(message: "Enter a name."); return }
        guard !selectedGroupID.isEmpty else { error = AppError(message: "Pick a care group."); return }
        isBusy = true; error = nil
        do {
            let response = try await session.api.createReceiver(
                path: .init(careGroupId: selectedGroupID),
                body: .json(.init(name: trimmed))
            )
            _ = try response.created.body.json
            onDone()
        } catch {
            self.error = AppError.from(error)
        }
        isBusy = false
    }
}

struct AddReceiverView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let me: Me
    let onAdded: () -> Void
    @State private var model = AddReceiverModel()

    private var adminGroups: [Me.Membership] { me.adminGroups }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $model.name)
                if adminGroups.count > 1 {
                    Picker("Care group", selection: $model.selectedGroupID) {
                        ForEach(adminGroups, id: \.careGroupID) { Text($0.name).tag($0.careGroupID) }
                    }
                }
                if let error = model.error {
                    Text(error.message).foregroundStyle(Theme.Colors.alert)
                }
            }
            .navigationTitle("Add receiver")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await model.create(using: session) { onAdded(); dismiss() } }
                    }.disabled(model.isBusy)
                }
            }
            .onAppear {
                if model.selectedGroupID.isEmpty { model.selectedGroupID = adminGroups.first?.careGroupID ?? "" }
            }
        }
    }
}
