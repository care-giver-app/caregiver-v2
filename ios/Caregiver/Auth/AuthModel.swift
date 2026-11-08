import Foundation
import os

/// The screens pushed over Landing. Only one is ever on the stack: Sign in and
/// Sign up swap rather than stack (PRD "Getting into the app").
enum AuthScreen: Hashable {
    case signIn, signUp
}

/// The one sheet Getting in raises. Its content changes in place: Reset password
/// moves from the address to the code, and becomes Confirm code for an account
/// never confirmed.
enum AuthSheet: Equatable {
    case confirmCode(ConfirmOrigin)
    case resetPassword(ResetStep)
}

/// What raised Confirm code, which decides where confirming goes.
enum ConfirmOrigin: Equatable {
    /// Over Sign in or Sign up: confirming signs in with the password just typed.
    case signIn, signUp
    /// In place of Reset password: confirming carries on with the reset.
    case resetPassword
}

enum ResetStep: Equatable {
    case address, codeAndPassword
}

/// A message in a `StrideAlertBanner`.
struct AuthBanner: Equatable {
    let message: String
    let tone: StrideAlertBanner.Tone

    static func error(_ message: String) -> AuthBanner { AuthBanner(message: message, tone: .error) }
    static func info(_ message: String) -> AuthBanner { AuthBanner(message: message, tone: .info) }
}

/// This device's saved sign-in for Face ID. Injected for tests.
@MainActor
struct DeviceSignIn {
    static let faceIDOfferedKey = "faceIDOffered"

    var credentials: () -> KeychainStore.Credentials? = { KeychainStore.credentials() }
    var save: (_ email: String, _ password: String) -> Void = { KeychainStore.save(email: $0, password: $1) }
    /// Removes the stored password and turns Face ID off — what Sign out does — and
    /// lets Offer Face ID be raised again once the caregiver signs in with a password.
    var forget: () -> Void = {
        SignOutAction.forgetOnThisDevice()
        UserDefaults.standard.set(false, forKey: DeviceSignIn.faceIDOfferedKey)
    }
    var biometryName: () -> String = { BiometricAuth.biometryName }
}

/// Getting in, from Landing to signed in: Sign in, Sign up, Confirm code, and
/// Reset password. Maps every Cognito answer to what the PRD says the caregiver
/// sees; the views only render it.
@MainActor
@Observable
final class AuthModel {
    /// The copy for each answer. Figma's where it has a frame (credentials incorrect,
    /// code incorrect, code expired, reset code invalid, reset code sent).
    enum Copy {
        static let incorrectCredentials = "Email or password was incorrect"
        // Figma (355:3278) names the minute the lock clears; the PRD says never to.
        static let locked = "Too many attempts. This account is locked for a few minutes, so try again shortly."
        static let alreadyHasAccount = "This address already has an account. Sign in to it here."
        static let codeIncorrect = "The code is incorrect"
        static let codeExpired = "The code has expired. Ask for another with Resend."
        static let resetCodeNotRight = "That code was invalid"
        static let resetCodeSent = "A code was sent to your email if an account already exists"
        static let passwordReset = "Your password is changed. Sign in with the new one."
        static let passwordsDoNotMatch = "Passwords do not match"
        static let invalidPassword = "Use at least 8 characters, with a lowercase letter and a number."
        static let rateLimited = "Too many tries. Wait a little while, then try again."
        static let missingCredentials = "Enter your email and password."
        static let missingSignUpFields = "Fill in every field to create your account."
        static let missingEmail = "Enter your email."

        static func storedPasswordRejected(_ biometry: String) -> String {
            "Your password has changed. Sign in with it to use \(biometry) again."
        }
    }

    /// Sixty seconds between codes, so a double tap on Resend does not replace a
    /// code before it arrives (PRD).
    static let resendWait: TimeInterval = 60

    var path: [AuthScreen] = []
    var sheet: AuthSheet?

    var email = ""
    var password = ""
    var confirmPassword = ""
    var firstName = ""
    var lastName = ""
    var code = ""
    var newPassword = ""

    /// The banner on Sign in or Sign up.
    private(set) var formBanner: AuthBanner?
    /// The banner in the sheet.
    private(set) var sheetBanner: AuthBanner?
    private(set) var isBusy = false
    /// When the last code was sent, of any kind; Resend waits `resendWait` from it.
    private(set) var codeSentAt: Date?

    /// The name typed on Sign up, given to an account never confirmed once the
    /// caregiver confirms it — that is the signup they meant to finish.
    private var nameToApply: (given: String, family: String)?

    /// Re-runs the sign-in resolution (`session.refresh()`), which decides Home or Join.
    var onSignedIn: () async -> Void = {}

    private let service: AuthService
    private let reconciler: AuthSessionReconciling
    private let device: DeviceSignIn
    private let now: () -> Date

    nonisolated private static let log = Logger(subsystem: "caretosher.caregiverapp.ios", category: "auth")

    init(service: AuthService = AmplifyAuthService(),
         reconciler: AuthSessionReconciling = AmplifyAuthSessionReconciler(),
         device: DeviceSignIn = DeviceSignIn(),
         now: @escaping () -> Date = Date.init) {
        self.service = service
        self.reconciler = reconciler
        self.device = device
        self.now = now
    }

    private var address: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Navigation

    /// Landing → Sign in or Sign up (a push), or one to the other (a swap).
    func show(_ screen: AuthScreen) {
        formBanner = nil
        path = [screen]
    }

    /// Back to Landing with nothing left over, after a sign out or a lapsed session.
    /// The email stays, like Remember me's.
    func reset() {
        path = []
        sheet = nil
        formBanner = nil
        sheetBanner = nil
        password = ""
        confirmPassword = ""
        code = ""
        newPassword = ""
        nameToApply = nil
    }

    /// Dismissing either sheet returns to the screen underneath, form intact.
    func dismissSheet() {
        sheet = nil
        sheetBanner = nil
        code = ""
        newPassword = ""
        nameToApply = nil
    }

    // MARK: - Sign in

    func signIn() async {
        guard !isBusy else { return }
        guard !address.isEmpty, !password.isEmpty else {
            formBanner = .error(Copy.missingCredentials)
            return
        }
        isBusy = true
        formBanner = nil
        defer { isBusy = false }

        switch await attemptSignIn() {
        case .signedIn:
            await onSignedIn()
        case .unconfirmed:
            // Revealed only now the right password has been supplied (PRD).
            await raiseConfirmCode(.signIn)
        case .failed(let failure):
            formBanner = .error(Self.message(for: failure))
        }
    }

    /// Whether this device holds a password for Face ID.
    var hasStoredCredentials: Bool { device.credentials() != nil }

    /// Signs in with the stored password, once the biometric check has passed. A
    /// password the account no longer takes is cleared, so Face ID stops working
    /// loudly rather than silently, and the caregiver signs in by hand (PRD).
    func signInWithBiometrics() async {
        guard !isBusy, let stored = device.credentials() else { return }
        email = stored.email
        password = stored.password
        isBusy = true
        formBanner = nil
        defer { isBusy = false }

        switch await attemptSignIn() {
        case .signedIn:
            await onSignedIn()
        case .unconfirmed:
            await raiseConfirmCode(.signIn)
        case .failed(let failure):
            if failure == .incorrectCredentials {
                device.forget()
                password = ""
                formBanner = .error(Copy.storedPasswordRejected(device.biometryName()))
            } else {
                formBanner = .error(Self.message(for: failure))
            }
            // Raised from Landing at launch: land where the message can be acted on.
            if path.isEmpty { path = [.signIn] }
        }
    }

    // MARK: - Sign up

    func signUp() async {
        guard !isBusy else { return }
        let given = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !given.isEmpty, !family.isEmpty, !address.isEmpty, !password.isEmpty else {
            formBanner = .error(Copy.missingSignUpFields)
            return
        }
        guard password == confirmPassword else {
            formBanner = .error(Copy.passwordsDoNotMatch)
            return
        }
        isBusy = true
        formBanner = nil
        defer { isBusy = false }

        do {
            let needsConfirmation = try await service.signUp(email: address, password: password,
                                                             givenName: given, familyName: family)
            if needsConfirmation {
                nameToApply = nil
                codeWasSent()
                code = ""
                sheetBanner = nil
                sheet = .confirmCode(.signUp)
            } else {
                await finishSignIn()
            }
        } catch {
            let failure = AuthFailure.classify(error)
            if failure == .usernameExists {
                await answerExistingAccount(given: given, family: family)
            } else {
                formBanner = .error(Self.message(for: failure))
            }
        }
    }

    /// The address already has an account. Which kind decides where the caregiver
    /// goes, as far as the password just typed can tell (PRD).
    private func answerExistingAccount(given: String, family: String) async {
        switch await attemptSignIn() {
        case .unconfirmed:
            // Never confirmed, made with this password: finish that signup, with
            // the name just typed.
            nameToApply = (given, family)
            await raiseConfirmCode(.signUp)
        case .signedIn:
            // Confirmed, and the password is right. Not signed in from here: the
            // caregiver would think they had made a new account.
            await service.signOutLocally()
            swapToSignIn(with: .info(Copy.alreadyHasAccount))
        case .failed(.incorrectCredentials):
            swapToSignIn(with: .info(Copy.alreadyHasAccount))
        case .failed(.locked):
            swapToSignIn(with: .error(Copy.locked))
        case .failed(let failure):
            formBanner = .error(Self.message(for: failure))
        }
    }

    private func swapToSignIn(with banner: AuthBanner) {
        password = ""
        confirmPassword = ""
        path = [.signIn]
        formBanner = banner
    }

    // MARK: - Confirm code

    func confirmCode() async {
        guard !isBusy, case .confirmCode(let origin) = sheet else { return }
        guard code.count == 6 else {
            sheetBanner = .error(Copy.codeIncorrect)
            return
        }
        isBusy = true
        sheetBanner = nil
        defer { isBusy = false }

        do {
            try await service.confirmSignUp(email: address, code: code)
        } catch {
            sheetBanner = .error(Self.message(for: AuthFailure.classify(error)))
            return
        }

        switch origin {
        case .resetPassword:
            // Not signed in: not knowing the password is why they came.
            await continueReset()
        case .signIn, .signUp:
            await finishSignIn()
        }
    }

    /// After confirming over Sign in or Sign up: sign in with the password still in
    /// memory, so the caregiver is not asked for it a second time.
    private func finishSignIn() async {
        switch await attemptSignIn() {
        case .signedIn:
            if let name = nameToApply {
                nameToApply = nil
                await applyName(name)
            }
            sheet = nil
            code = ""
            await onSignedIn()
        case .unconfirmed:
            sheet = nil
            formBanner = .error(AppError.unknown.message)
        case .failed(let failure):
            sheet = nil
            formBanner = .error(Self.message(for: failure))
        }
    }

    /// Gives the account the name typed on Sign up, then refreshes the tokens: the
    /// API provisions the caregiver from the ID token, which must carry the new name.
    private func applyName(_ name: (given: String, family: String)) async {
        do {
            try await service.updateName(givenName: name.given, familyName: name.family)
            try await service.forceRefreshSession()
        } catch {
            Self.log.error("updating the name after confirming failed: \(String(describing: error), privacy: .public)")
        }
    }

    func resendCode() async {
        guard !isBusy, canResend else { return }
        do {
            try await service.resendSignUpCode(email: address)
            codeWasSent()
            code = ""
            sheetBanner = nil
        } catch {
            sheetBanner = .error(Self.message(for: AuthFailure.classify(error)))
        }
    }

    /// Seconds until Resend is available again, at `date`.
    func resendSecondsRemaining(at date: Date) -> Int {
        guard let sent = codeSentAt else { return 0 }
        let left = Self.resendWait - date.timeIntervalSince(sent)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }

    var canResend: Bool { resendSecondsRemaining(at: now()) == 0 }

    private func codeWasSent() { codeSentAt = now() }

    /// Sends a fresh confirmation code and raises Confirm code.
    private func raiseConfirmCode(_ origin: ConfirmOrigin) async {
        code = ""
        sheetBanner = nil
        do {
            try await service.resendSignUpCode(email: address)
            codeWasSent()
        } catch {
            sheetBanner = .error(Self.message(for: AuthFailure.classify(error)))
        }
        sheet = .confirmCode(origin)
    }

    // MARK: - Reset password

    func openResetPassword() {
        code = ""
        newPassword = ""
        sheetBanner = nil
        sheet = .resetPassword(.address)
    }

    func sendResetCode() async {
        guard !isBusy else { return }
        guard !address.isEmpty else {
            sheetBanner = .error(Copy.missingEmail)
            return
        }
        isBusy = true
        sheetBanner = nil
        defer { isBusy = false }

        do {
            try await service.resetPassword(email: address)
            moveToResetCode()
        } catch {
            let failure = AuthFailure.classify(error)
            if failure == .neverConfirmed {
                // Cannot be reset; confirm it first, then the reset carries on.
                await raiseConfirmCode(.resetPassword)
            } else {
                sheetBanner = .error(Self.message(for: failure))
            }
        }
    }

    /// After Confirm code raised in place of Reset password: send the reset code
    /// and return to the code and a new password.
    private func continueReset() async {
        do {
            try await service.resetPassword(email: address)
            moveToResetCode()
        } catch {
            code = ""
            sheet = .resetPassword(.address)
            sheetBanner = .error(Self.message(for: AuthFailure.classify(error)))
        }
    }

    private func moveToResetCode() {
        codeWasSent()
        code = ""
        newPassword = ""
        sheetBanner = nil
        sheet = .resetPassword(.codeAndPassword)
    }

    /// Back to the address; the code already sent is discarded.
    func backToAddress() {
        code = ""
        newPassword = ""
        sheetBanner = nil
        sheet = .resetPassword(.address)
    }

    func setNewPassword() async {
        guard !isBusy else { return }
        isBusy = true
        sheetBanner = nil
        defer { isBusy = false }

        do {
            try await service.confirmResetPassword(email: address, newPassword: newPassword, code: code)
        } catch {
            switch AuthFailure.classify(error) {
            case .codeMismatch, .codeExpired:
                // One answer for both, so a caregiver never sent a code cannot tell
                // which it was (PRD).
                sheetBanner = .error(Copy.resetCodeNotRight)
            case let failure:
                sheetBanner = .error(Self.message(for: failure))
            }
            return
        }

        // The stored password is now wrong; ending other sessions is deferred
        // (docs/TECH_DEBT.md).
        device.forget()
        sheet = nil
        code = ""
        newPassword = ""
        password = ""
        path = [.signIn]
        formBanner = .info(Copy.passwordReset)
    }

    // MARK: - Face ID

    /// Offer Face ID is raised once, the first time a caregiver reaches Home on a
    /// device that supports it — and only with a password in hand to store.
    static func shouldOfferFaceID(biometryAvailable: Bool, enabled: Bool, alreadyOffered: Bool,
                                  hasPassword: Bool) -> Bool {
        biometryAvailable && !enabled && !alreadyOffered && hasPassword
    }

    var hasPasswordInMemory: Bool { !password.isEmpty && !address.isEmpty }

    func enableBiometrics() {
        device.save(address, password)
    }

    // MARK: - Shared

    private enum Attempt: Equatable {
        case signedIn, unconfirmed
        case failed(AuthFailure)
    }

    private func attemptSignIn() async -> Attempt {
        // The app's signed-out state and Amplify's can disagree — a session whose
        // refresh token expired leaves Amplify signedIn while the app falls back to
        // the auth screen. Signing in from there throws `invalidState` until the
        // dead session is cleared.
        let local = await reconciler.localState()
        switch SignInPreflight.decide(local: local, signingInAs: address) {
        case .alreadySignedIn:
            // Tokens are good and ours: the app only *thought* it was signed out.
            return .signedIn
        case .clearThenProceed:
            await reconciler.clearLocalSession()
        case .unreachable:
            // Never destroy a refresh token we can't prove is dead.
            return .failed(.network)
        case .proceed:
            break
        }
        do {
            switch try await service.signIn(email: address, password: password) {
            case .signedIn: return .signedIn
            case .confirmSignUp: return .unconfirmed
            case .unsupported: return .failed(.other)
            }
        } catch {
            let failure = AuthFailure.classify(error)
            return failure == .userNotConfirmed ? .unconfirmed : .failed(failure)
        }
    }

    static func message(for failure: AuthFailure) -> String {
        switch failure {
        case .incorrectCredentials: Copy.incorrectCredentials
        case .locked: Copy.locked
        case .codeMismatch: Copy.codeIncorrect
        case .codeExpired: Copy.codeExpired
        case .invalidPassword: Copy.invalidPassword
        case .rateLimited: Copy.rateLimited
        case .network: AppError.transport.message
        case .userNotConfirmed, .usernameExists, .neverConfirmed, .other: AppError.unknown.message
        }
    }
}

#if DEBUG
extension AuthModel {
    /// A model showing one Getting in state, for previews. Bound to `ios/fixtures.md`:
    /// Trevor's address.
    static func preview(path: [AuthScreen] = [], sheet: AuthSheet? = nil,
                        formBanner: AuthBanner? = nil, sheetBanner: AuthBanner? = nil) -> AuthModel {
        let model = AuthModel(device: DeviceSignIn(credentials: { nil }, save: { _, _ in }, forget: {}))
        model.email = GettingInFixtures.trevorNoTeam.email
        model.path = path
        model.sheet = sheet
        model.formBanner = formBanner
        model.sheetBanner = sheetBanner
        return model
    }
}
#endif
