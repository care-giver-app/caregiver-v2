import Foundation
import CaregiverAPI

/// Pure resolution of a user id → display name within a member list.
enum MemberDirectory {
    static func displayName(forUser id: String, in members: [Components.Schemas.Member]) -> String {
        members.first { $0.userId == id }?.name ?? "A care-team member"
    }
}

/// Shared, lazily-loaded cache of care-group members keyed by care_group_id.
/// Reused across screens so event-detail doesn't refetch on every tap.
@MainActor
@Observable
final class MembersStore {
    private var byGroup: [String: [Components.Schemas.Member]] = [:]
    private var loading: Set<String> = []

    /// Resolves a logged_by id to a name, loading the group roster on first use.
    /// Returns the fallback while loading or if the id is unknown.
    func name(forUser id: String, inGroup careGroupID: String, using session: Session) async -> String {
        if let members = byGroup[careGroupID] {
            return MemberDirectory.displayName(forUser: id, in: members)
        }
        await load(careGroupID, using: session)
        return MemberDirectory.displayName(forUser: id, in: byGroup[careGroupID] ?? [])
    }

    private func load(_ careGroupID: String, using session: Session) async {
        guard byGroup[careGroupID] == nil, !loading.contains(careGroupID) else { return }
        loading.insert(careGroupID)
        defer { loading.remove(careGroupID) }
        do {
            let response = try await session.api.listMembers(path: .init(careGroupId: careGroupID))
            byGroup[careGroupID] = try response.ok.body.json
        } catch {
            byGroup[careGroupID] = []  // cache empty → fallback, avoids refetch storm
        }
    }
}
