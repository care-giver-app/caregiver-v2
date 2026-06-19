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
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 160)
            Spacer()
            VStack(spacing: Theme.Spacing.sm) {
                Text("Welcome, \(userName)!")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.ink)
                Text("Create a care team to get started. A care team connects caregivers and the people they look after.")
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            GlassField(placeholder: "Care team name", icon: "person.2", text: $model.name)
                .textContentType(.organizationName)
                .autocorrectionDisabled()
            if let error = model.error {
                Text(error.message).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
            }
            PrimaryButton(title: "Create team", isLoading: model.isBusy) {
                Task { await model.create(using: session) }
            }
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .earthBackground()
    }
}

#Preview {
    let session = Session(bootstrap: { throw Session.NotSignedIn() }, signOutHandler: {})
    CreateGroupView(userName: "Trevor")
        .environment(session)
}
