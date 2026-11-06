import Foundation

/// Join a care team: accept an invitation waiting for your email, or paste an invite code.
@MainActor
@Observable
final class JoinCareTeamModel {
    enum Invitations: Equatable {
        case loading
        case loaded([PendingInvitation])
        /// The list could not be fetched. Shown as its own state, never as an empty
        /// list, which would read as nobody having invited you (PRD).
        case failed
    }

    /// A pasted code the app will not take. The PRD: invalid, expired, and already
    /// used all read the same way.
    static let codeNoLongerValid = AppError(message: "This invite code is no longer valid")
    /// A listed invitation that expired or was used since the list appeared.
    static let invitationNoLongerValid = AppError(message: "That invitation is no longer valid.")
    /// The failed state's banner, shown where the list goes.
    static let invitationsFailedMessage = "Couldn't load your invitations."

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

    /// Fetches the invitations. A list already on screen stays there until the
    /// answer replaces it, so a re-fetch does not flash a spinner.
    func load() async {
        do {
            invitations = .loaded(try await service.listInvitations())
        } catch {
            invitations = .failed
        }
    }

    /// Try again, from the failed state.
    func retry() async {
        invitations = .loading
        await load()
    }

    func accept(_ invitation: PendingInvitation) async {
        guard !isBusy else { return }
        acceptingCode = invitation.code
        defer { acceptingCode = nil }
        if await redeem(invitation.code) == .noLongerValid {
            // Stale since the list appeared: say so, and fetch the list again so
            // the dead row is not left there to be tapped twice.
            error = Self.invitationNoLongerValid
            await load()
        }
    }

    func joinWithCode() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing pasted: the PRD names no message for this, so no call and no message.
        guard !trimmed.isEmpty, !isBusy else { return }
        isJoining = true
        defer { isJoining = false }
        if await redeem(trimmed) == .noLongerValid {
            error = Self.codeNoLongerValid
        }
    }

    /// Redeems `code`, handling every answer but `.noLongerValid`, whose message
    /// depends on whether the code came from the list or was pasted. Returns the
    /// outcome, or nil when the call threw.
    private func redeem(_ code: String) async -> RedeemOutcome? {
        error = nil
        do {
            let outcome = try await service.redeem(code)
            switch outcome {
            case .joined, .alreadyMember:
                // 409 is not an error: they are on a team now, so the sign-in
                // resolution runs again and lands them there (PRD).
                await onJoined()
            case .noLongerValid:
                break
            case .rejected(let message):
                error = AppError.forStatus(400, serverMessage: message)
            }
            return outcome
        } catch {
            self.error = AppError.from(error)
            return nil
        }
    }
}
