import Foundation

/// Where the last care receiver a caregiver looked at is kept on this device, one per
/// signed-in account (PRD "Home": "the last one a caregiver looked at on this device").
struct LastReceiverStore: Sendable {
    var read: @Sendable (_ accountKey: String) -> String?
    var write: @Sendable (_ accountKey: String, _ receiverID: String) -> Void

    static let standard = LastReceiverStore(
        read: { UserDefaults.standard.string(forKey: key($0)) },
        write: { UserDefaults.standard.set($1, forKey: key($0)) }
    )

    static func key(_ accountKey: String) -> String { "v1.lastReceiverID.\(accountKey)" }

    /// Kept in memory only, for tests and previews; `seed` maps account keys to receiver ids.
    static func inMemory(_ seed: [String: String] = [:]) -> LastReceiverStore {
        let box = Box(seed)
        return LastReceiverStore(read: { box.get($0) }, write: { box.set($0, $1) })
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String]
        init(_ values: [String: String]) { self.values = values }
        func get(_ k: String) -> String? { lock.withLock { values[k] } }
        func set(_ k: String, _ v: String) { lock.withLock { values[k] = v } }
    }
}

/// A care receiver together with the care team they are on, which Home's header names.
struct TeamedReceiver: Equatable, Sendable {
    let receiver: TeamReceiver
    let team: Account.Team
}

/// Who Home is about. The app chooses rather than asking: the last receiver this
/// caregiver looked at on this device, or the first alphabetically across all their
/// teams when there is no last one. Archived receivers are never chosen — the API does
/// not list them — so a remembered receiver who has been archived (or is gone) is
/// chosen again by the same rule (PRD "Home").
@MainActor
@Observable
final class ActiveReceiverModel {
    enum Phase: Equatable {
        case loading
        case active(TeamedReceiver)
        /// Nobody on any team to care for; `team` is the one Home describes — the first
        /// of the caregiver's teams — and `canManage` whether they are its admin.
        case noReceivers(team: Account.Team, canManage: Bool)
        case failed(AppError)
    }

    private(set) var phase: Phase = .loading
    /// Every non-archived receiver across the caregiver's teams, alphabetically.
    private(set) var receivers: [TeamedReceiver] = []

    let account: Account
    private let service: TrackersService
    private let store: LastReceiverStore

    init(account: Account, service: TrackersService, store: LastReceiverStore = .standard) {
        self.account = account
        self.service = service
        self.store = store
    }

    var active: TeamedReceiver? {
        if case .active(let r) = phase { r } else { nil }
    }

    /// Remembered per account; the email is the pool's username, so it is the account's
    /// one stable handle the app holds.
    private var accountKey: String { account.email.lowercased() }

    func load() async {
        let teams = account.teams
        let service = service
        do {
            let lists = try await withThrowingTaskGroup(of: (Int, [TeamReceiver]).self) { group in
                for (i, team) in teams.enumerated() {
                    group.addTask { (i, try await service.listReceivers(team.teamID)) }
                }
                var byTeam: [Int: [TeamReceiver]] = [:]
                for try await (i, list) in group { byTeam[i] = list }
                return byTeam
            }
            let all = teams.indices.flatMap { i in
                (lists[i] ?? []).map { TeamedReceiver(receiver: $0.managed(by: teams[i]), team: teams[i]) }
            }
            receivers = Self.alphabetical(all)
            settle()
        } catch {
            phase = .failed(AppError.from(error))
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// Makes `receiverID` the one Home is about and remembers it — how Team switches.
    /// One not among those loaded (just added, say) is looked up afresh.
    func choose(_ receiverID: String) async {
        store.write(accountKey, receiverID)
        if let found = receivers.first(where: { $0.receiver.id == receiverID }) {
            phase = .active(found)
        } else {
            await load()
        }
    }

    private func settle() {
        guard let chosen = Self.choose(from: receivers, remembered: store.read(accountKey)) else {
            if let team = account.teams.first {
                phase = .noReceivers(team: team, canManage: team.role == "admin")
            } else {
                // `.v1Ready` always has a team; nothing true can be said without one.
                phase = .failed(.unknown)
            }
            return
        }
        store.write(accountKey, chosen.receiver.id)
        phase = .active(chosen)
    }

    // MARK: - The rule

    /// The remembered receiver if they are still listed, otherwise the first of `candidates`
    /// alphabetically; nil when there is nobody.
    nonisolated static func choose(from candidates: [TeamedReceiver], remembered: String?) -> TeamedReceiver? {
        if let remembered, let found = candidates.first(where: { $0.receiver.id == remembered }) {
            return found
        }
        return alphabetical(candidates).first
    }

    /// By name, ignoring case; a tie keeps the order given (team order, then the API's).
    nonisolated static func alphabetical(_ candidates: [TeamedReceiver]) -> [TeamedReceiver] {
        candidates.enumerated().sorted { a, b in
            switch a.element.receiver.name.localizedCaseInsensitiveCompare(b.element.receiver.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.offset < b.offset
            }
        }.map(\.element)
    }
}
