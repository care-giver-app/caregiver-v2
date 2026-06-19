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

    func role(inCareGroup id: String) -> String? {
        memberships.first { $0.careGroupID == id }?.role
    }

    /// The care team (care-group) display name for a group id, if the user is a member.
    func teamName(forCareGroup id: String) -> String? {
        memberships.first { $0.careGroupID == id }?.name
    }

    func isAdmin(inCareGroup id: String) -> Bool {
        role(inCareGroup: id) == "admin"
    }

    /// Memberships where the caller is an admin (can add receivers/trackers).
    var adminGroups: [Membership] {
        memberships.filter { $0.role == "admin" }
    }
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
    private(set) var signedOutExplicitly = false

    let client: Client?
    private let bootstrap: () async throws -> Me
    private let signOutHandler: () async -> Void

    /// The configured client; only call from feature screens (always present at runtime).
    var api: Client { client! }

    /// Testable initializer.
    init(client: Client? = nil,
         bootstrap: @escaping () async throws -> Me,
         signOutHandler: @escaping () async -> Void) {
        self.client = client
        self.bootstrap = bootstrap
        self.signOutHandler = signOutHandler
    }

    /// Production initializer: real Amplify sign-in check + GET /me.
    convenience init() {
        let client = APIClient.make(tokenProvider: CognitoTokenProvider())
        self.init(
            client: client,
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
            signedOutExplicitly = false
            state = me.memberships.isEmpty ? .onboarding(me) : .ready(me)
        } catch {
            state = .signedOut
        }
    }

    func signOut() async {
        await signOutHandler()
        signedOutExplicitly = true
        state = .signedOut
    }
}
