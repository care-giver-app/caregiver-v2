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
    @Environment(MembersStore.self) private var members
    @Environment(\.dismiss) private var dismiss
    let tracker: Components.Schemas.Tracker
    let event: Components.Schemas.Event
    let onChanged: () -> Void
    @State private var model = EventDetailModel()
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var loggedByName = "A care-team member"

    private var rows: [DynamicFormBuilder.ValueRow] {
        DynamicFormBuilder.rows(values: event.values, fields: tracker.fields)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                headerCard
                valuesCard
                if let note = event.note, !note.isEmpty { noteCard(note) }
                actions
                if let error = model.error {
                    Text(error).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.alert)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .earthBackground()
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loggedByName = await members.name(
                forUser: event.loggedBy, inGroup: event.careGroupId, using: session)
        }
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(Color(hex: tracker.color ?? "397234"))
                    .frame(width: 12, height: 12)
                if let icon = tracker.icon, !icon.isEmpty {
                    Image(systemName: icon).foregroundStyle(Theme.Colors.textPrimary)
                }
                Text(tracker.name).font(Theme.Typography.title).foregroundStyle(Theme.Colors.textPrimary)
            }
            Text(occurredAtText).font(Theme.Typography.subhead).foregroundStyle(Theme.Colors.textSecondary)
            Text("Logged by \(loggedByName)").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private var valuesCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(row.unit.map { "\(row.value) \($0)" } ?? row.value)
                        .font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Note").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textTertiary)
            Text(note).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            PrimaryButton(title: "Edit") { showEdit = true }
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete").font(Theme.Typography.headline).frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md - 3)
            }
            .foregroundStyle(Theme.Colors.alert)
            .disabled(model.isBusy)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var occurredAtText: String {
        let date = event.occurredAt
        let absolute = date.formatted(date: .abbreviated, time: .shortened)
        let relative = date.formatted(.relative(presentation: .named))
        return "\(absolute) · \(relative)"
    }
}
