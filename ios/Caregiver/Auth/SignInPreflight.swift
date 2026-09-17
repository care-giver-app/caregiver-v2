import Foundation
import Amplify
import AWSCognitoAuthPlugin

/// What Amplify believes about the session it has stored locally.
///
/// Amplify runs its own auth state machine, and it does **not** sign out
/// locally when a refresh token expires: it stays `.signedIn` and flags the
/// stored credentials dead. `Amplify.Auth.signIn` refuses to run in that state
/// — "There is already a user in signedIn state. SignOut the user first before
/// calling signIn" — so sign-in has to reconcile before asking for new tokens.
enum LocalSessionState: Equatable {
    /// Nothing stored — signing in is safe.
    case none
    /// Stored tokens are usable, and belong to `username`.
    case valid(username: String)
    /// A stored session that can no longer be refreshed.
    case expired
    /// Can't tell: the device is offline and the session may still be good.
    case unreachable

    /// Reads a `getCognitoTokens()` failure. Only an explicit network failure
    /// counts as unknown — everything else is a session we must clear, because
    /// leaving a dead one in place is what strands the user on sign-in.
    static func classify(tokenFailure error: AuthError) -> LocalSessionState {
        if case .service(_, _, let underlying) = error,
           let cognito = underlying as? AWSCognitoAuthError,
           case .network = cognito {
            return .unreachable
        }
        return .expired
    }
}

/// What sign-in must do before calling `Amplify.Auth.signIn`.
enum SignInPreflight: Equatable {
    /// Call `signIn` directly.
    case proceed
    /// Clear Amplify's stored session first, then call `signIn`.
    case clearThenProceed
    /// The stored session is good and belongs to this user — re-bootstrap the
    /// app instead of re-authenticating.
    case alreadySignedIn
    /// Leave the stored session alone; it may still be good once the network is.
    case unreachable

    /// The user pool uses the email as the username, so a stored session
    /// belongs to this sign-in attempt when the two match.
    static func decide(local: LocalSessionState, signingInAs email: String) -> SignInPreflight {
        switch local {
        case .none:
            return .proceed
        case .expired:
            return .clearThenProceed
        case .unreachable:
            return .unreachable
        case .valid(let username):
            // An unknown username falls through to clearing: a needless re-auth
            // is cheap, signing someone into another person's account is not.
            return normalized(username) == normalized(email) && !username.isEmpty
                ? .alreadySignedIn
                : .clearThenProceed
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
