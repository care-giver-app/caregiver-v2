import SwiftUI
import CaregiverAPI

/// Model for the Aurora add-receiver sheet. Creates a receiver (name-only for v1 —
/// DOB deferred, receivers.md decision 4), refreshes `ReceiverContext`, and
/// auto-switches to the newcomer (decision 9). API-touching, so smoke-tested.
@MainActor
@Observable
final class AddReceiverModelAurora {
    var name = ""
    var selectedGroupID = ""
    var isBusy = false
    var errorMessage: String?

    func create(using session: Session, context: ReceiverContext, onAdded: () -> Void) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        guard !selectedGroupID.isEmpty else { errorMessage = "Pick a care group."; return }
        isBusy = true; errorMessage = nil
        do {
            let response = try await session.api.createReceiver(
                path: .init(careGroupId: selectedGroupID),
                body: .json(.init(name: trimmed))
            )
            let created = try response.created.body.json
            await context.load(using: session)
            // The POST response is authoritative; guarantee the newcomer is present
            // even if listReceivers hasn't caught up (read-after-write lag), so the
            // auto-switch below never resolves to the wrong receiver.
            if !context.receivers.contains(where: { $0.receiverId == created.receiverId }) {
                context.receivers.append(created)
            }
            context.activeReceiverID = created.receiverId   // auto-switch (decision 9)
            onAdded()
        } catch {
            errorMessage = AppError.from(error).message
        }
        isBusy = false
    }
}

/// Aurora "Add care receiver" sheet, presented from the switch sheet. Name-only
/// (receivers.md decision 4); admin-gated by the caller. Detent `.medium` (decision 8).
struct AddReceiverSheet: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    @Environment(\.dismiss) private var dismiss
    let me: Me
    /// Called after a successful add so the presenting switch sheet can dismiss too.
    let onAdded: () -> Void

    @State private var model = AddReceiverModelAurora()

    private var adminGroups: [Me.Membership] { me.adminGroups }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Add care receiver")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)

            StrideField(placeholder: "Name", icon: "person", text: $model.name)

            if adminGroups.count > 1 {
                groupPicker
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.alert)
            }

            Spacer(minLength: 0)

            StrideButton(title: "Add receiver", isLoading: model.isBusy) {
                Task {
                    await model.create(using: session, context: context) {
                        onAdded()
                        dismiss()
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .strideBackground()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isBusy)
        .onAppear {
            if model.selectedGroupID.isEmpty {
                model.selectedGroupID = adminGroups.first?.careGroupID ?? ""
            }
        }
    }

    private var groupPicker: some View {
        Menu {
            ForEach(adminGroups, id: \.careGroupID) { group in
                Button(group.name) { model.selectedGroupID = group.careGroupID }
            }
        } label: {
            HStack {
                Text(adminGroups.first { $0.careGroupID == model.selectedGroupID }?.name ?? "Care group")
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(Theme.Typography.body)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
            }
        }
    }
}
