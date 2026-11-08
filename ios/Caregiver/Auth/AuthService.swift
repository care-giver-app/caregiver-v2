import Foundation
import Amplify
import AWSCognitoAuthPlugin

/// The Cognito calls Getting in makes, behind a seam so `AuthModel` can be tested
/// without Amplify. Every call throws whatever Amplify throws; `AuthFailure.classify`
/// reads it.
protocol AuthService: Sendable {
    /// Creates the account. True when Cognito wants the emailed code confirmed
    /// first (always, for this pool); false when the account is already usable.
    func signUp(email: String, password: String, givenName: String, familyName: String) async throws -> Bool
    func signIn(email: String, password: String) async throws -> SignInStep
    func confirmSignUp(email: String, code: String) async throws
    func resendSignUpCode(email: String) async throws
    func resetPassword(email: String) async throws
    func confirmResetPassword(email: String, newPassword: String, code: String) async throws
    /// Sets the signed-in account's given and family name.
    func updateName(givenName: String, familyName: String) async throws
    /// Fetches fresh tokens, so the ID token carries attributes just changed.
    func forceRefreshSession() async throws
    /// Clears this device's session; no other device is touched.
    func signOutLocally() async
}

/// Where `signIn` left the caregiver.
enum SignInStep: Equatable {
    case signedIn
    /// The account exists and the password is right, but it was never confirmed.
    case confirmSignUp
    /// Any other challenge (MFA, new password). This pool sets none up.
    case unsupported
}

/// What a Cognito answer means for Getting in. Cognito's own messages never reach
/// the screen: each case has the copy the PRD asks for, in `AuthModel`.
enum AuthFailure: Error, Equatable {
    /// A wrong password, or an address with no account — Cognito answers both alike.
    case incorrectCredentials
    /// Five failed attempts: the account is locked for a while.
    case locked
    /// Sign in with the right password on an account never confirmed.
    case userNotConfirmed
    case usernameExists
    case codeMismatch
    case codeExpired
    /// Forgot password on an account never confirmed: there is no verified address
    /// to send a reset code to.
    case neverConfirmed
    /// The password does not meet the pool's policy.
    case invalidPassword
    /// Too many requests or codes in a short while.
    case rateLimited
    case network
    case other

    /// Reads an error thrown by Amplify. Anything unrecognized is `.other`.
    static func classify(_ error: Error) -> AuthFailure {
        if let failure = error as? AuthFailure { return failure }
        guard let authError = error as? AuthError else {
            return error is URLError ? .network : .other
        }
        switch authError {
        case .notAuthorized(let message, _, _):
            // Cognito says "Password attempts exceeded" once the account is locked,
            // and "Incorrect username or password." otherwise.
            return message.localizedCaseInsensitiveContains("attempts exceeded") ? .locked : .incorrectCredentials
        case .service(let message, _, let underlying):
            guard let cognito = underlying as? AWSCognitoAuthError else { return .other }
            switch cognito {
            case .userNotConfirmed: return .userNotConfirmed
            case .usernameExists: return .usernameExists
            case .codeMismatch: return .codeMismatch
            case .codeExpired: return .codeExpired
            case .invalidPassword: return .invalidPassword
            case .limitExceeded, .requestLimitExceeded, .failedAttemptsLimitExceeded, .limitExceededException:
                return .rateLimited
            case .network: return .network
            case .invalidParameter:
                // "Cannot reset password for the user as there is no registered/verified
                // email or phone_number" — the one InvalidParameter Getting in expects.
                return message.localizedCaseInsensitiveContains("verified") ? .neverConfirmed : .other
            default: return .other
            }
        default:
            return .other
        }
    }
}

/// `AuthService` on Amplify.
struct AmplifyAuthService: AuthService {
    func signUp(email: String, password: String, givenName: String, familyName: String) async throws -> Bool {
        let attributes = [
            AuthUserAttribute(.email, value: email),
            AuthUserAttribute(.givenName, value: givenName),
            AuthUserAttribute(.familyName, value: familyName),
        ]
        let result = try await Amplify.Auth.signUp(username: email, password: password,
                                                   options: .init(userAttributes: attributes))
        if case .confirmUser = result.nextStep { return true }
        return false
    }

    func signIn(email: String, password: String) async throws -> SignInStep {
        let result = try await Amplify.Auth.signIn(username: email, password: password)
        if result.isSignedIn { return .signedIn }
        // Amplify turns UserNotConfirmedException into this step rather than throwing.
        if case .confirmSignUp = result.nextStep { return .confirmSignUp }
        return .unsupported
    }

    func confirmSignUp(email: String, code: String) async throws {
        _ = try await Amplify.Auth.confirmSignUp(for: email, confirmationCode: code)
    }

    func resendSignUpCode(email: String) async throws {
        _ = try await Amplify.Auth.resendSignUpCode(for: email)
    }

    func resetPassword(email: String) async throws {
        _ = try await Amplify.Auth.resetPassword(for: email)
    }

    func confirmResetPassword(email: String, newPassword: String, code: String) async throws {
        try await Amplify.Auth.confirmResetPassword(for: email, with: newPassword, confirmationCode: code)
    }

    func updateName(givenName: String, familyName: String) async throws {
        _ = try await Amplify.Auth.update(userAttributes: [
            AuthUserAttribute(.givenName, value: givenName),
            AuthUserAttribute(.familyName, value: familyName),
        ])
    }

    func forceRefreshSession() async throws {
        _ = try await Amplify.Auth.fetchAuthSession(options: .forceRefresh())
    }

    func signOutLocally() async {
        _ = await Amplify.Auth.signOut()
    }
}
