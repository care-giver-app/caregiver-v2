import XCTest
import Amplify
import AWSCognitoAuthPlugin
@testable import Caregiver

// Cognito's answers, as Amplify 2.58.2 throws them (observed against dev Cognito,
// whose pool has preventUserExistenceErrors on).
private enum Cognito {
    static let incorrect = AuthError.notAuthorized("Incorrect username or password.", "", nil)
    static let locked = AuthError.notAuthorized("Password attempts exceeded", "", nil)
    static let notConfirmed = service(.userNotConfirmed, "User is not confirmed.")
    static let usernameExists = service(.usernameExists, "An account with the given email already exists.")
    static let codeMismatch = service(.codeMismatch, "Invalid verification code provided, please try again.")
    static let codeExpired = service(.codeExpired, "Invalid code provided, please request a code again.")
    static let neverConfirmed = service(.invalidParameter,
        "Cannot reset password for the user as there is no registered/verified email or phone_number")
    static let limitExceeded = service(.limitExceeded, "Attempt limit exceeded, please try after some time.")

    static func service(_ error: AWSCognitoAuthError, _ message: String) -> AuthError {
        .service(message, "", error)
    }
}

/// A scripted `AuthService` that records every call, in order, in a shared log.
private final class FakeAuthService: AuthService, @unchecked Sendable {
    let log: CallLog
    var signUpNeedsConfirmation = true
    var signUpError: Error?
    /// Answers to successive `signIn` calls; the last repeats.
    var signInAnswers: [Result<SignInStep, Error>] = [.success(.signedIn)]
    var confirmSignUpError: Error?
    var resendError: Error?
    var resetPasswordError: Error?
    var confirmResetError: Error?

    init(log: CallLog) { self.log = log }

    func signUp(email: String, password: String, givenName: String, familyName: String) async throws -> Bool {
        log.record("signUp \(email) \(givenName) \(familyName)")
        if let signUpError { throw signUpError }
        return signUpNeedsConfirmation
    }

    func signIn(email: String, password: String) async throws -> SignInStep {
        log.record("signIn \(email) \(password)")
        let answer = signInAnswers.count > 1 ? signInAnswers.removeFirst() : signInAnswers[0]
        return try answer.get()
    }

    func confirmSignUp(email: String, code: String) async throws {
        log.record("confirmSignUp \(code)")
        if let confirmSignUpError { throw confirmSignUpError }
    }

    func resendSignUpCode(email: String) async throws {
        log.record("resendSignUpCode")
        if let resendError { throw resendError }
    }

    func resetPassword(email: String) async throws {
        log.record("resetPassword")
        if let resetPasswordError { throw resetPasswordError }
    }

    func confirmResetPassword(email: String, newPassword: String, code: String) async throws {
        log.record("confirmResetPassword \(code)")
        if let confirmResetError { throw confirmResetError }
    }

    func updateName(givenName: String, familyName: String) async throws {
        log.record("updateName \(givenName) \(familyName)")
    }

    func forceRefreshSession() async throws { log.record("forceRefreshSession") }

    func signOutLocally() async { log.record("signOutLocally") }
}

private final class CallLog: @unchecked Sendable {
    private(set) var calls: [String] = []
    func record(_ call: String) { calls.append(call) }
}

private struct NoStoredSession: AuthSessionReconciling {
    func localState() async -> LocalSessionState { .none }
    func clearLocalSession() async {}
}

@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

@MainActor
final class AuthModelTests: XCTestCase {
    private var log: CallLog!
    private var service: FakeAuthService!
    private var clock: Clock!
    private var stored: KeychainStore.Credentials?
    private var forgot = 0

    override func setUp() async throws {
        log = CallLog()
        service = FakeAuthService(log: log)
        clock = Clock()
        stored = nil
        forgot = 0
    }

    private func makeModel() -> AuthModel {
        let device = DeviceSignIn(
            credentials: { [unowned self] in stored },
            save: { [unowned self] email, password in stored = .init(email: email, password: password) },
            forget: { [unowned self] in stored = nil; forgot += 1 },
            biometryName: { "Face ID" }
        )
        let model = AuthModel(service: service, reconciler: NoStoredSession(), device: device,
                              now: { [clock] in clock!.now })
        model.onSignedIn = { [log] in log!.record("onSignedIn") }
        model.email = "trevor@example.com"
        model.password = "hunter22"
        return model
    }

    private func signUpForm(_ model: AuthModel) {
        model.firstName = "Trevor"
        model.lastName = "Williams"
        model.confirmPassword = model.password
    }

    // MARK: - Reading Cognito's answers

    func testWrongPasswordAndUnknownAddressReadAsIncorrectCredentials() {
        // Cognito answers both with the same NotAuthorizedException.
        XCTAssertEqual(AuthFailure.classify(Cognito.incorrect), .incorrectCredentials)
    }

    func testPasswordAttemptsExceededReadsAsLocked() {
        XCTAssertEqual(AuthFailure.classify(Cognito.locked), .locked)
    }

    func testUserNotConfirmedIsRead() {
        XCTAssertEqual(AuthFailure.classify(Cognito.notConfirmed), .userNotConfirmed)
    }

    func testUsernameExistsIsRead() {
        XCTAssertEqual(AuthFailure.classify(Cognito.usernameExists), .usernameExists)
    }

    func testCodeMismatchAndExpiredAreReadApart() {
        XCTAssertEqual(AuthFailure.classify(Cognito.codeMismatch), .codeMismatch)
        XCTAssertEqual(AuthFailure.classify(Cognito.codeExpired), .codeExpired)
    }

    func testResetOnANeverConfirmedAccountIsRead() {
        XCTAssertEqual(AuthFailure.classify(Cognito.neverConfirmed), .neverConfirmed)
        XCTAssertEqual(AuthFailure.classify(Cognito.service(.invalidParameter, "1 validation error detected")),
                       .other)
    }

    func testRateLimitsReadAsRateLimited() {
        XCTAssertEqual(AuthFailure.classify(Cognito.limitExceeded), .rateLimited)
        XCTAssertEqual(AuthFailure.classify(Cognito.service(.requestLimitExceeded, "Too many requests")),
                       .rateLimited)
    }

    func testNetworkFailureIsRead() {
        XCTAssertEqual(AuthFailure.classify(Cognito.service(.network, "offline")), .network)
    }

    // MARK: - Sign in

    func testSignInSuccessRunsTheSignInResolution() async {
        let model = makeModel()
        await model.signIn()
        XCTAssertEqual(log.calls, ["signIn trevor@example.com hunter22", "onSignedIn"])
    }

    func testIncorrectCredentialsSaySoAndNothingMore() async {
        service.signInAnswers = [.failure(Cognito.incorrect)]
        let model = makeModel()
        await model.signIn()
        XCTAssertEqual(model.formBanner, .error("Email or password was incorrect"))
        XCTAssertFalse(log.calls.contains("onSignedIn"))
    }

    func testLockedAccountSaysLockedWithoutATime() async {
        service.signInAnswers = [.failure(Cognito.locked)]
        let model = makeModel()
        await model.signIn()
        XCTAssertEqual(model.formBanner, .error(AuthModel.Copy.locked))
        XCTAssertTrue(AuthModel.Copy.locked.contains("few minutes"))
    }

    func testRightPasswordOnAnUnconfirmedAccountSendsAFreshCode() async {
        service.signInAnswers = [.success(.confirmSignUp)]
        let model = makeModel()
        await model.signIn()
        XCTAssertEqual(log.calls, ["signIn trevor@example.com hunter22", "resendSignUpCode"])
        XCTAssertEqual(model.sheet, .confirmCode(.signIn))
        XCTAssertFalse(model.canResend)
    }

    func testUnconfirmedThrownRatherThanStepIsReadTheSame() async {
        service.signInAnswers = [.failure(Cognito.notConfirmed)]
        let model = makeModel()
        await model.signIn()
        XCTAssertEqual(model.sheet, .confirmCode(.signIn))
    }

    func testRateLimitedSignInSaysToWait() async {
        service.signInAnswers = [.failure(Cognito.limitExceeded)]
        let model = makeModel()
        await model.signIn()
        XCTAssertEqual(model.formBanner, .error(AuthModel.Copy.rateLimited))
    }

    func testConfirmingOverSignInSignsInWithThePasswordInMemory() async {
        service.signInAnswers = [.success(.confirmSignUp), .success(.signedIn)]
        let model = makeModel()
        await model.signIn()
        model.code = "123456"
        await model.confirmCode()
        XCTAssertEqual(log.calls, ["signIn trevor@example.com hunter22", "resendSignUpCode",
                                   "confirmSignUp 123456", "signIn trevor@example.com hunter22", "onSignedIn"])
        XCTAssertNil(model.sheet)
    }

    // MARK: - Sign up

    func testSignUpOnANewAddressRaisesConfirmCode() async {
        let model = makeModel()
        signUpForm(model)
        await model.signUp()
        XCTAssertEqual(log.calls, ["signUp trevor@example.com Trevor Williams"])
        XCTAssertEqual(model.sheet, .confirmCode(.signUp))
        XCTAssertEqual(model.resendSecondsRemaining(at: clock.now), 60)
    }

    func testMismatchedPasswordsAreCaughtBeforeCognito() async {
        let model = makeModel()
        signUpForm(model)
        model.confirmPassword = "different1"
        await model.signUp()
        XCTAssertEqual(model.formBanner, .error(AuthModel.Copy.passwordsDoNotMatch))
        XCTAssertTrue(log.calls.isEmpty)
    }

    func testExistingUnconfirmedAccountMadeWithThisPasswordFinishesWithTheNameJustTyped() async {
        service.signUpError = Cognito.usernameExists
        service.signInAnswers = [.success(.confirmSignUp), .success(.signedIn)]
        let model = makeModel()
        signUpForm(model)
        await model.signUp()
        XCTAssertEqual(model.sheet, .confirmCode(.signUp))

        model.code = "654321"
        await model.confirmCode()
        // The name lands, and the tokens refresh, before the API sees the caregiver.
        XCTAssertEqual(log.calls, [
            "signUp trevor@example.com Trevor Williams",
            "signIn trevor@example.com hunter22",
            "resendSignUpCode",
            "confirmSignUp 654321",
            "signIn trevor@example.com hunter22",
            "updateName Trevor Williams",
            "forceRefreshSession",
            "onSignedIn",
        ])
    }

    func testExistingConfirmedAccountWithTheRightPasswordIsNotSignedIn() async {
        service.signUpError = Cognito.usernameExists
        service.signInAnswers = [.success(.signedIn)]
        let model = makeModel()
        signUpForm(model)
        await model.signUp()
        XCTAssertEqual(log.calls.last, "signOutLocally")
        XCTAssertFalse(log.calls.contains("onSignedIn"))
        XCTAssertEqual(model.path, [.signIn])
        XCTAssertEqual(model.email, "trevor@example.com")
        XCTAssertEqual(model.formBanner, .info(AuthModel.Copy.alreadyHasAccount))
        XCTAssertNil(model.sheet)
    }

    func testExistingAccountWithAnotherPasswordSwapsToSignIn() async {
        service.signUpError = Cognito.usernameExists
        service.signInAnswers = [.failure(Cognito.incorrect)]
        let model = makeModel()
        signUpForm(model)
        await model.signUp()
        XCTAssertEqual(model.path, [.signIn])
        XCTAssertEqual(model.email, "trevor@example.com")
        XCTAssertEqual(model.password, "")
        XCTAssertEqual(model.formBanner, .info(AuthModel.Copy.alreadyHasAccount))
    }

    func testExistingLockedAccountSwapsToSignInSayingLocked() async {
        service.signUpError = Cognito.usernameExists
        service.signInAnswers = [.failure(Cognito.locked)]
        let model = makeModel()
        signUpForm(model)
        await model.signUp()
        XCTAssertEqual(model.path, [.signIn])
        XCTAssertEqual(model.formBanner, .error(AuthModel.Copy.locked))
    }

    // MARK: - Confirm code

    func testWrongCodeSaysTheCodeIsWrong() async {
        service.confirmSignUpError = Cognito.codeMismatch
        let model = makeModel()
        model.sheet = .confirmCode(.signUp)
        model.code = "111111"
        await model.confirmCode()
        XCTAssertEqual(model.sheetBanner, .error("The code is incorrect"))
        XCTAssertEqual(model.sheet, .confirmCode(.signUp))
    }

    func testExpiredCodeSaysToAskForAnother() async {
        service.confirmSignUpError = Cognito.codeExpired
        let model = makeModel()
        model.sheet = .confirmCode(.signUp)
        model.code = "111111"
        await model.confirmCode()
        XCTAssertEqual(model.sheetBanner, .error(AuthModel.Copy.codeExpired))
        XCTAssertNotEqual(AuthModel.Copy.codeExpired, AuthModel.Copy.codeIncorrect)
    }

    func testResendWaitsSixtySecondsAfterAnyCode() async {
        let model = makeModel()
        signUpForm(model)
        await model.signUp()

        clock.advance(30)
        XCTAssertEqual(model.resendSecondsRemaining(at: clock.now), 30)
        await model.resendCode()
        XCTAssertFalse(log.calls.contains("resendSignUpCode"))

        clock.advance(29.5)
        XCTAssertFalse(model.canResend)
        clock.advance(0.5)
        XCTAssertTrue(model.canResend)

        model.code = "12"
        await model.resendCode()
        XCTAssertEqual(log.calls.last, "resendSignUpCode")
        XCTAssertEqual(model.code, "")
        XCTAssertEqual(model.resendSecondsRemaining(at: clock.now), 60)
    }

    func testDismissingConfirmCodeReturnsToTheFormUnderneath() async {
        let model = makeModel()
        model.path = [.signUp]
        signUpForm(model)
        await model.signUp()
        model.dismissSheet()
        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.path, [.signUp])
        XCTAssertEqual(model.firstName, "Trevor")
    }

    // MARK: - Reset password

    func testSendMeACodeAnswersEveryAddressAlike() async {
        let model = makeModel()
        model.openResetPassword()
        await model.sendResetCode()
        XCTAssertEqual(model.sheet, .resetPassword(.codeAndPassword))
        XCTAssertNil(model.sheetBanner)
        XCTAssertFalse(model.canResend)
    }

    func testResetOnANeverConfirmedAccountConfirmsFirstThenCarriesOn() async {
        service.resetPasswordError = Cognito.neverConfirmed
        let model = makeModel()
        model.password = ""
        model.openResetPassword()
        await model.sendResetCode()
        XCTAssertEqual(log.calls, ["resetPassword", "resendSignUpCode"])
        XCTAssertEqual(model.sheet, .confirmCode(.resetPassword))

        service.resetPasswordError = nil
        model.code = "222222"
        await model.confirmCode()
        // Not signed in: confirming carries on with the reset.
        XCTAssertEqual(log.calls, ["resetPassword", "resendSignUpCode", "confirmSignUp 222222", "resetPassword"])
        XCTAssertEqual(model.sheet, .resetPassword(.codeAndPassword))
        XCTAssertEqual(model.code, "")
    }

    func testBackToTheAddressDiscardsTheCode() async {
        let model = makeModel()
        model.openResetPassword()
        await model.sendResetCode()
        model.code = "333"
        model.newPassword = "newpass1"
        model.backToAddress()
        XCTAssertEqual(model.sheet, .resetPassword(.address))
        XCTAssertEqual(model.code, "")
        XCTAssertEqual(model.newPassword, "")

        await model.sendResetCode()
        XCTAssertEqual(log.calls, ["resetPassword", "resetPassword"])
    }

    func testWrongAndExpiredResetCodesReadTheSame() async {
        let model = makeModel()
        model.sheet = .resetPassword(.codeAndPassword)

        service.confirmResetError = Cognito.codeMismatch
        await model.setNewPassword()
        let wrong = model.sheetBanner

        service.confirmResetError = Cognito.codeExpired
        await model.setNewPassword()
        XCTAssertEqual(model.sheetBanner, wrong)
        XCTAssertEqual(wrong, .error("That code was invalid"))
    }

    func testResetEndsAtSignInNotSignedInWithStoredCredentialsCleared() async {
        stored = .init(email: "trevor@example.com", password: "oldpass1")
        let model = makeModel()
        model.path = [.signIn]
        model.sheet = .resetPassword(.codeAndPassword)
        model.code = "444444"
        model.newPassword = "newpass1"
        await model.setNewPassword()
        XCTAssertEqual(forgot, 1)
        XCTAssertNil(stored)
        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.path, [.signIn])
        XCTAssertEqual(model.email, "trevor@example.com")
        XCTAssertEqual(model.password, "")
        XCTAssertFalse(log.calls.contains { $0.hasPrefix("signIn") })
        XCTAssertFalse(log.calls.contains("onSignedIn"))
    }

    // MARK: - Face ID

    func testFaceIDSignsInWithTheStoredPassword() async {
        stored = .init(email: "trevor@example.com", password: "stored11")
        let model = makeModel()
        model.email = ""
        model.password = ""
        await model.signInWithBiometrics()
        XCTAssertEqual(log.calls, ["signIn trevor@example.com stored11", "onSignedIn"])
    }

    func testARejectedStoredPasswordIsClearedAndAsksForThePassword() async {
        stored = .init(email: "trevor@example.com", password: "oldpass1")
        service.signInAnswers = [.failure(Cognito.incorrect)]
        let model = makeModel()
        await model.signInWithBiometrics()
        XCTAssertEqual(forgot, 1)
        XCTAssertNil(stored)
        XCTAssertEqual(model.password, "")
        XCTAssertEqual(model.path, [.signIn])
        XCTAssertEqual(model.formBanner, .error(AuthModel.Copy.storedPasswordRejected("Face ID")))
    }

    func testFaceIDIsOfferedOnceWithAPasswordInHand() {
        XCTAssertTrue(AuthModel.shouldOfferFaceID(biometryAvailable: true, enabled: false,
                                                  alreadyOffered: false, hasPassword: true))
        XCTAssertFalse(AuthModel.shouldOfferFaceID(biometryAvailable: true, enabled: false,
                                                   alreadyOffered: true, hasPassword: true))
        XCTAssertFalse(AuthModel.shouldOfferFaceID(biometryAvailable: true, enabled: false,
                                                   alreadyOffered: false, hasPassword: false))
        XCTAssertFalse(AuthModel.shouldOfferFaceID(biometryAvailable: false, enabled: false,
                                                   alreadyOffered: false, hasPassword: true))
        XCTAssertFalse(AuthModel.shouldOfferFaceID(biometryAvailable: true, enabled: true,
                                                   alreadyOffered: false, hasPassword: true))
    }

    func testEnablingFaceIDStoresTheCredentials() {
        let model = makeModel()
        model.enableBiometrics()
        XCTAssertEqual(stored?.email, "trevor@example.com")
        XCTAssertEqual(stored?.password, "hunter22")
    }
}
