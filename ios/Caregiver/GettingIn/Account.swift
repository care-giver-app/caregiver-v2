import Foundation

/// App-side view of `GET /v1/me`: the signed-in caregiver and the care teams they
/// belong to. Kept apart from the old `Me` so the flag-off path is untouched.
struct Account: Equatable, Sendable {
    struct Team: Equatable, Sendable {
        let teamID: String
        let name: String
        let role: String
    }
    let name: String
    let email: String
    let teams: [Team]
}
