import Foundation

/// App-side view of `GET /v1/me`: the signed-in caregiver and the care teams they
/// belong to. Kept apart from the old `Me` so the flag-off path is untouched.
struct Account: Equatable, Sendable {
    struct Team: Equatable, Hashable, Identifiable, Sendable {
        let teamID: String
        let name: String
        let role: String

        var id: String { teamID }
    }
    let name: String
    let email: String
    let teams: [Team]
    /// The caregiver's id (`Caregiver.user_id`), which marks their own row on a care team's
    /// roster. Empty where a caller had no reason to know it.
    var userID: String = ""
}
