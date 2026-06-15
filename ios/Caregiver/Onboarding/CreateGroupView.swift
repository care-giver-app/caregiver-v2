import SwiftUI

@MainActor
@Observable
final class CreateGroupModel {
    var name = ""
    var isBusy = false
    var error: AppError?

    func create(using session: Session) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = AppError(message: "Enter a group name."); return }
        isBusy = true; error = nil
        do {
            let response = try await session.api.createCareGroup(body: .json(.init(name: trimmed)))
            _ = try response.created.body.json
            await session.refresh() // re-bootstrap -> .ready
        } catch {
            self.error = AppError.from(error)
        }
        isBusy = false
    }
}

struct CreateGroupView: View {
    @Environment(Session.self) private var session
    let userName: String
    @State private var model = CreateGroupModel()

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Welcome, \(userName)").font(Theme.Typography.title)
            Text("Create a care group to get started.")
                .font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.textSecondary)
            TextField("Care group name", text: $model.name)
                .textFieldStyle(.roundedBorder)
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Create group", isLoading: model.isBusy) {
                Task { await model.create(using: session) }
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }
}
