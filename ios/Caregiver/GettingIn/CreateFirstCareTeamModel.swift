import Foundation

/// Create your first care team: a name, then `POST /v1/teams`.
@MainActor
@Observable
final class CreateFirstCareTeamModel {
    static let nameRequired = AppError(message: "Enter a care team name.")

    var name = ""
    private(set) var isBusy = false
    private(set) var error: AppError?

    private let service: GettingInService
    private let onCreated: () async -> Void

    /// `onCreated` re-runs the sign-in resolution (`session.refresh()`).
    init(service: GettingInService, onCreated: @escaping () async -> Void) {
        self.service = service
        self.onCreated = onCreated
    }

    func create() async {
        guard !isBusy else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = Self.nameRequired; return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            switch try await service.createTeam(trimmed) {
            case .created:
                await onCreated()
            case .rejected(let message):
                error = AppError.forStatus(400, serverMessage: message)
            }
        } catch {
            self.error = AppError.from(error)
        }
    }
}
