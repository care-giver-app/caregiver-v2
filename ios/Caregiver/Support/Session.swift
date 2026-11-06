import Foundation
import Amplify
import CaregiverAPI
import os

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
        /// Flag `v1_api` on: signed in, on no care team → Join a care team.
        case v1NoTeam(Account)
        /// Flag `v1_api` on: signed in, on at least one care team.
        case v1Ready(Account)
    }

    private(set) var state: State = .checking
    private(set) var signedOutExplicitly = false

    let client: Client?
    private let bootstrap: () async throws -> Me
    private let bootstrapV1: () async throws -> Account
    private let fetchFlags: @Sendable () async throws -> FeatureFlags
    private let flagsTimeout: Duration
    private let signOutHandler: () async -> Void

    /// The configured client; only call from feature screens (always present at runtime).
    var api: Client { client! }

    /// Testable initializer. `fetchFlags` defaults to every flag off, so callers
    /// that only know the old path keep it.
    init(client: Client? = nil,
         bootstrap: @escaping () async throws -> Me,
         bootstrapV1: @escaping () async throws -> Account = { throw NotSignedIn() },
         fetchFlags: @escaping @Sendable () async throws -> FeatureFlags = { FeatureFlags() },
         flagsTimeout: Duration = .seconds(5),
         signOutHandler: @escaping () async -> Void) {
        self.client = client
        self.bootstrap = bootstrap
        self.bootstrapV1 = bootstrapV1
        self.fetchFlags = fetchFlags
        self.flagsTimeout = flagsTimeout
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
            bootstrapV1: {
                let authSession = try await Amplify.Auth.fetchAuthSession()
                guard authSession.isSignedIn else { throw NotSignedIn() }
                let response = try await client.getMyAccount()
                let account = try response.ok.body.json
                return Account(
                    name: account.caregiver.name,
                    email: account.caregiver.email,
                    teams: account.teams.map {
                        Account.Team(teamID: $0.teamId, name: $0.name, role: $0.role.rawValue)
                    }
                )
            },
            fetchFlags: {
                FeatureFlags(try await client.getFlags().ok.body.json)
            },
            signOutHandler: { _ = await Amplify.Auth.signOut() }
        )
    }

    nonisolated private static let log = Logger(subsystem: "caretosher.caregiverapp.ios", category: "session")

    struct NotSignedIn: Error {}

    func refresh() async {
        state = .checking
        let useV1 = await isV1APIEnabled()
        do {
            if useV1 {
                let account = try await bootstrapV1()
                signedOutExplicitly = false
                state = account.teams.isEmpty ? .v1NoTeam(account) : .v1Ready(account)
            } else {
                let me = try await bootstrap()
                signedOutExplicitly = false
                state = me.memberships.isEmpty ? .onboarding(me) : .ready(me)
            }
        } catch {
            state = .signedOut
        }
    }

    struct FlagsTimedOut: Error {}

    /// `GET /flags` → `v1_api`. Any failure reads as off: the old path is the safe one.
    /// Bounded by `flagsTimeout` so a slow flags call cannot hold up the old path.
    private func isV1APIEnabled() async -> Bool {
        let fetch = fetchFlags
        let timeout = flagsTimeout
        do {
            let flags = try await withThrowingTaskGroup(of: FeatureFlags.self) { group in
                group.addTask { try await fetch() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw FlagsTimedOut()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw FlagsTimedOut() }
                return first
            }
            let on = flags.isEnabled(FeatureFlags.v1API)
            Self.log.info("GET /flags ok: v1_api=\(on, privacy: .public)")
            return on
        } catch {
            Self.log.error("GET /flags failed, v1_api off: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func signOut() async {
        await signOutHandler()
        signedOutExplicitly = true
        state = .signedOut
    }
}
