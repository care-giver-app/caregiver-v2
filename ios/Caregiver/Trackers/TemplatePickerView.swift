import SwiftUI
import CaregiverAPI

@MainActor
@Observable
final class TemplatePickerModel {
    enum State: Equatable {
        case loading
        case loaded([Components.Schemas.TrackerTemplate])
        case error(String)
    }
    private(set) var state: State = .loading
    var creatingId: String?

    func load(using session: Session) async {
        state = .loading
        do {
            let response = try await session.api.listTrackerTemplates()
            state = .loaded(try response.ok.body.json)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }

    /// Clones a template into a new tracker. Returns an error message or nil.
    func create(from template: Components.Schemas.TrackerTemplate, receiverId: String, using session: Session) async -> String? {
        creatingId = template.templateId
        defer { creatingId = nil }
        do {
            let body = Components.Schemas.TrackerWrite(
                name: template.name, kind: template.kind,
                icon: template.icon, color: template.color, fields: template.fields
            )
            _ = try await session.api.createTracker(path: .init(receiverId: receiverId), body: .json(body))
            return nil
        } catch { return AppError.from(error).message }
    }
}

struct TemplatePickerView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let receiverId: String
    let onCreated: () -> Void
    @State private var model = TemplatePickerModel()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading: StrideLoadingView()
                case .error(let m): StrideErrorState(message: m) { Task { await model.load(using: session) } }
                case .loaded(let templates):
                    List(templates, id: \.templateId) { template in
                        Button {
                            Task {
                                if let message = await model.create(from: template, receiverId: receiverId, using: session) {
                                    error = message
                                } else { onCreated(); dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(template.name).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                                    Text("\(template.fields.count) field(s)").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                if model.creatingId == template.templateId { ProgressView() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add tracker")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Couldn't create tracker", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .task { await model.load(using: session) }
        }
    }
}
