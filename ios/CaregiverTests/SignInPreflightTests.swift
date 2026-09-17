import XCTest
import Amplify
import AWSCognitoAuthPlugin
@testable import Caregiver

/// Amplify does not sign out locally when a refresh token expires — it stays in
/// its `.signedIn` state and marks the credentials dead. `Amplify.Auth.signIn`
/// then refuses to run ("There is already a user in signedIn state"), which is
/// what stranded Face ID users on the sign-in screen after their session ended.
final class SignInPreflightTests: XCTestCase {

    func testExpiredSessionIsClearedBeforeSigningIn() {
        XCTAssertEqual(
            SignInPreflight.decide(local: .expired, signingInAs: "ann@example.com"),
            .clearThenProceed
        )
    }

    func testNoStoredSessionSignsInDirectly() {
        XCTAssertEqual(
            SignInPreflight.decide(local: .none, signingInAs: "ann@example.com"),
            .proceed
        )
    }

    func testValidSessionForTheSameUserRebootstrapsInstead() {
        // The session is fine; the app only *thought* it was signed out because
        // bootstrap failed for some other reason. Re-authenticating is wasted
        // work, and it needs a network the user may not have.
        XCTAssertEqual(
            SignInPreflight.decide(local: .valid(username: "Ann@Example.com "),
                                   signingInAs: " ann@example.com"),
            .alreadySignedIn
        )
    }

    func testValidSessionForADifferentUserIsCleared() {
        XCTAssertEqual(
            SignInPreflight.decide(local: .valid(username: "ann@example.com"),
                                   signingInAs: "bob@example.com"),
            .clearThenProceed
        )
    }

    func testValidSessionWithAnUnknownUserIsCleared() {
        XCTAssertEqual(
            SignInPreflight.decide(local: .valid(username: ""),
                                   signingInAs: "ann@example.com"),
            .clearThenProceed
        )
    }

    func testUnreachableSessionIsLeftAlone() {
        // Never destroy a refresh token we cannot prove is dead.
        XCTAssertEqual(
            SignInPreflight.decide(local: .unreachable, signingInAs: "ann@example.com"),
            .unreachable
        )
    }

    // MARK: - Classifying why the stored tokens failed

    func testSessionExpiredCountsAsExpired() {
        let error = AuthError.sessionExpired("expired", "sign in again", nil)
        XCTAssertEqual(LocalSessionState.classify(tokenFailure: error), .expired)
    }

    func testNotAuthorizedCountsAsExpired() {
        let error = AuthError.notAuthorized("not authorized", "sign in again", nil)
        XCTAssertEqual(LocalSessionState.classify(tokenFailure: error), .expired)
    }

    func testNetworkFailureIsUnreachableNotExpired() {
        let error = AuthError.service("offline", "check your connection",
                                      AWSCognitoAuthError.network)
        XCTAssertEqual(LocalSessionState.classify(tokenFailure: error), .unreachable)
    }

    func testUnrecognizedFailureCountsAsExpired() {
        // Erring toward "expired" costs one silent re-auth; erring the other way
        // strands the user, which is the bug being fixed.
        let error = AuthError.unknown("who knows", nil)
        XCTAssertEqual(LocalSessionState.classify(tokenFailure: error), .expired)
    }
}
