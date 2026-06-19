import Foundation
import Amplify

@MainActor
@Observable
final class AuthModel {
    var email = ""
    var password = ""
    var confirmPassword = ""
    var firstName = ""
    var lastName = ""
    var code = ""
    var newPassword = ""
    var resetCodeSent = false
    var isBusy = false
    var error: AppError?
    var needsConfirmation = false

    /// Called by the owner (Session) after a successful sign-in to re-bootstrap.
    var onSignedIn: () async -> Void = {}

    func signUp() async {
        guard password == confirmPassword else {
            error = AppError(message: "Passwords do not match")
            return
        }
        await run {
            let attrs = [
                AuthUserAttribute(.email, value: self.email),
                AuthUserAttribute(.givenName, value: self.firstName),
                AuthUserAttribute(.familyName, value: self.lastName),
            ]
            let result = try await Amplify.Auth.signUp(
                username: self.email, password: self.password,
                options: .init(userAttributes: attrs)
            )
            if case .confirmUser = result.nextStep { self.needsConfirmation = true }
            else { await self.signIn() }
        }
    }

    func confirm() async {
        await run {
            _ = try await Amplify.Auth.confirmSignUp(for: self.email, confirmationCode: self.code)
            self.needsConfirmation = false
            await self.signIn()
        }
    }

    func signIn() async {
        await run {
            let result = try await Amplify.Auth.signIn(username: self.email, password: self.password)
            if result.isSignedIn { await self.onSignedIn() }
            else if case .confirmSignUp = result.nextStep { self.needsConfirmation = true }
        }
    }

    func sendResetCode() async {
        await run {
            _ = try await Amplify.Auth.resetPassword(for: self.email)
            self.resetCodeSent = true
        }
    }

    func signInWithBiometrics() async {
        guard let creds = KeychainStore.credentials() else { return }
        email = creds.email
        password = creds.password
        await signIn()
    }

    func enableBiometrics() {
        KeychainStore.save(email: email, password: password)
    }

    func disableBiometrics() {
        KeychainStore.delete()
    }

    func confirmReset() async {
        await run {
            try await Amplify.Auth.confirmResetPassword(
                for: self.email,
                with: self.newPassword,
                confirmationCode: self.code
            )
            self.resetCodeSent = false
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true; error = nil
        do { try await work() }
        catch { self.error = AppError(message: friendly(error)) }
        isBusy = false
    }

    private func friendly(_ error: Error) -> String {
        // Amplify surfaces AuthError; show its recovery-friendly description.
        if let authError = error as? AuthError { return authError.errorDescription }
        return AppError.unknown.message
    }
}
