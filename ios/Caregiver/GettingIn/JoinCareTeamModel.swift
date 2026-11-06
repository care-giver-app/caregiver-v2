import Foundation

/// Join a care team: accept an invitation waiting for your email, or paste an invite code.
@MainActor
@Observable
final class JoinCareTeamModel {
    enum Invitations: Equatable {
        case loading
        case loaded([PendingInvitation])
        case failed(AppError)
    }

    /// The PRD: invalid, expired, and already used all read the same way.
    static let noLongerValid = AppError(message: "This invite code is no longer valid")
    /// The PRD is silent on this copy (reported as a gap).
    static let alreadyMember = AppError(message: "You're already on this care team")

    private(set) var invitations: Invitations = .loading
    var code = ""
    /// The invitation whose Accept is in flight, if any.
    private(set) var acceptingCode: String?
    /// True while a pasted code is being redeemed.
    private(set) var isJoining = false
    /// The banner under the invite-code field.
    private(set) var error: AppError?

    private let service: GettingInService
    private let onJoined: () async -> Void

    /// `onJoined` re-runs the sign-in resolution (`session.refresh()`).
    init(service: GettingInService, onJoined: @escaping () async -> Void) {
        self.service = service
        self.onJoined = onJoined
    }

    var isBusy: Bool { acceptingCode != nil || isJoining }

    func load() async {
        do {
            invitations = .loaded(try await service.listInvitations())
        } catch {
            invitations = .failed(AppError.from(error))
        }
    }

    func accept(_ invitation: PendingInvitation) async {
        guard !isBusy else { return }
        acceptingCode = invitation.code
        defer { acceptingCode = nil }
        await redeem(invitation.code)
    }

    func joinWithCode() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing pasted: the PRD names no message for this, so no call and no message.
        guard !trimmed.isEmpty, !isBusy else { return }
        isJoining = true
        defer { isJoining = false }
        await redeem(trimmed)
    }

    private func redeem(_ code: String) async {
        error = nil
        do {
            switch try await service.redeem(code) {
            case .joined:
                await onJoined()
            case .noLongerValid:
                error = Self.noLongerValid
            case .alreadyMember:
                error = Self.alreadyMember
            case .rejected(let message):
                error = AppError.forStatus(400, serverMessage: message)
            }
        } catch {
            self.error = AppError.from(error)
        }
    }
}
