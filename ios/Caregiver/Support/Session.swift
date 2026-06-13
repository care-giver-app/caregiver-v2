import Foundation
import Amplify
import CaregiverAPI

/// App-side view of the current user + their care-group memberships.
struct Me: Equatable {
    struct Membership: Equatable {
        let careGroupID: String
        let name: String
        let role: String
    }
    let userName: String
    let memberships: [Membership]
}

@MainActor
@Observable
final class Session {
    enum State: Equatable {
        case checking
        case signedOut
        case onboarding(Me)
        case ready(Me)
    }

    private(set) var state: State = .checking

    private let bootstrap: () async throws -> Me
    private let signOutHandler: () async -> Void

    /// Testable initializer.
    init(bootstrap: @escaping () async throws -> Me,
         signOutHandler: @escaping () async -> Void) {
        self.bootstrap = bootstrap
        self.signOutHandler = signOutHandler
    }

    /// Production initializer: real Amplify sign-in check + GET /me.
    convenience init() {
        let client = APIClient.make(tokenProvider: CognitoTokenProvider())
        self.init(
            bootstrap: {
                // Only call /me when Amplify reports a signed-in session.
                let authSession = try await Amplify.Auth.fetchAuthSession()
                guard authSession.isSignedIn else { throw NotSignedIn() }
                let response = try await client.getMe()
                let me = try response.ok.body.json
                return Me(
                    userName: me.user.name,
                    memberships: me.memberships.map {
                        Me.Membership(careGroupID: $0.careGroupId, name: $0.name, role: $0.role.rawValue)
                    }
                )
            },
            signOutHandler: { _ = await Amplify.Auth.signOut() }
        )
    }

    struct NotSignedIn: Error {}

    func refresh() async {
        state = .checking
        do {
            let me = try await bootstrap()
            state = me.memberships.isEmpty ? .onboarding(me) : .ready(me)
        } catch {
            state = .signedOut
        }
    }

    func signOut() async {
        await signOutHandler()
        state = .signedOut
    }
}
