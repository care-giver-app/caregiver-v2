import SwiftUI
import CaregiverAPI

@MainActor
@Observable
final class EventDetailModel {
    var isBusy = false
    var error: String?

    func delete(trackerId: String, eventId: String, using session: Session) async -> Bool {
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            _ = try await session.api.deleteEvent(path: .init(trackerId: trackerId, eventId: eventId))
            return true
        } catch { self.error = AppError.from(error).message; return false }
    }
}

struct EventDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let tracker: Components.Schemas.Tracker
    let event: Components.Schemas.Event
    let onChanged: () -> Void
    @State private var model = EventDetailModel()
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Reading") {
                Text(DynamicFormBuilder.display(values: event.values, fields: tracker.fields))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if let note = event.note, !note.isEmpty {
                Section("Note") { Text(note) }
            }
            Section {
                Button("Edit") { showEdit = true }
                Button("Delete", role: .destructive) { confirmDelete = true }.disabled(model.isBusy)
            }
            if let error = model.error { Text(error).foregroundStyle(Theme.Colors.alert) }
        }
        .navigationTitle("Reading")
        .sheet(isPresented: $showEdit) {
            LogEventView(tracker: tracker, existing: event) { onChanged(); dismiss() }
        }
        .confirmationDialog("Delete this reading?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete(trackerId: tracker.trackerId, eventId: event.eventId, using: session) {
                        onChanged(); dismiss()
                    }
                }
            }
        }
    }
}
