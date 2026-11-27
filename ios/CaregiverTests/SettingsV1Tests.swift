import XCTest
import HTTPTypes
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

private typealias S = Components.Schemas

private enum Fixed {
    static let trevor = SettingsAccount(name: "Trevor", email: "t@example.com", emailNotifications: true)
    static let account = Account(name: "Trevor", email: "t@example.com", teams: [], userID: "trevor")
    static let draft = FeedbackDraft(kind: .bug, message: "It broke", appVersion: "2.0.0 (142)",
                                     device: "iPhone18,1, iOS 26.1")
}

private struct Down: Error {}

/// Keeps what the closures were handed, in order.
private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func add(_ s: String) { lock.withLock { entries.append(s) } }
    var all: [String] { lock.withLock { entries } }
}

/// A device that keeps what Face ID was given, and whose biometric check answers `passes`.
@MainActor
private final class FakeDevice {
    var enabled = false
    var saved: (email: String, password: String)?
    var disabled = 0
    var passes = true

    var device: SettingsDevice {
        SettingsDevice(biometryAvailable: { true }, biometryName: { "Face ID" },
                       authenticate: { [self] _ in passes },
                       faceIDEnabled: { [self] in enabled },
                       enableFaceID: { [self] email, password in
                           saved = (email, password)
                           enabled = true
                       },
                       disableFaceID: { [self] in
                           disabled += 1
                           enabled = false
                       },
                       pushStatus: { .off }, appVersion: { "2.0.0 (142)" },
                       deviceDescription: { "iPhone18,1, iOS 26.1" })
    }
}

// MARK: - Settings

@MainActor
final class SettingsModelTests: XCTestCase {
    func testItShowsTheSignedInAccountAtOnceThenReadsTheRest() async {
        var s = SettingsService()
        s.account = { SettingsAccount(name: "Trevor", email: "t@example.com", emailNotifications: false) }
        let model = SettingsModel(account: Fixed.account, service: s, auth: SettingsAuth(), device: FakeDevice().device)
        XCTAssertEqual(model.account.name, "Trevor")
        XCTAssertFalse(model.isLoaded, "email notifications are not known yet")
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertFalse(model.account.emailNotifications)
    }

    func testAFailedReadSaysSoAndKeepsWhatIsKnown() async {
        var s = SettingsService()
        s.account = { throw Down() }
        let model = SettingsModel(account: Fixed.account, service: s, auth: SettingsAuth(), device: FakeDevice().device)
        await model.load()
        XCTAssertTrue(model.loadFailed)
        XCTAssertEqual(model.account.email, "t@example.com")
    }

    func testTurningEmailOffChangesTheAccount() async {
        let log = Log()
        var s = SettingsService()
        s.account = { Fixed.trevor }
        s.changeEmailNotifications = { on in
            log.add("email \(on)")
            return SettingsAccount(name: "Trevor", email: "t@example.com", emailNotifications: on)
        }
        let model = SettingsModel(account: Fixed.account, service: s, auth: SettingsAuth(), device: FakeDevice().device)
        await model.load()
        await model.setEmailNotifications(false)
        XCTAssertEqual(log.all, ["email false"])
        XCTAssertFalse(model.account.emailNotifications)
    }

    func testEmailCannotBeChangedBeforeItIsKnown() async {
        let log = Log()
        var s = SettingsService()
        s.changeEmailNotifications = { _ in log.add("changed"); return Fixed.trevor }
        let model = SettingsModel(account: Fixed.account, service: s, auth: SettingsAuth(), device: FakeDevice().device)
        await model.setEmailNotifications(false)
        XCTAssertEqual(log.all, [])
    }

    func testAFailedEmailChangeSaysSoAndLeavesItAsItWas() async {
        var s = SettingsService()
        s.account = { Fixed.trevor }
        s.changeEmailNotifications = { _ in throw Down() }
        let model = SettingsModel(account: Fixed.account, service: s, auth: SettingsAuth(), device: FakeDevice().device)
        await model.load()
        await model.setEmailNotifications(false)
        XCTAssertTrue(model.emailNotificationsFailed)
        XCTAssertTrue(model.account.emailNotifications)
    }

    func testTurningFaceIDOffForgetsThePasswordAtOnce() {
        let fake = FakeDevice()
        fake.enabled = true
        let model = SettingsModel(account: Fixed.account, service: SettingsService(), auth: SettingsAuth(),
                                  device: fake.device)
        XCTAssertTrue(model.faceIDOn)
        model.setFaceID(false)
        XCTAssertEqual(fake.disabled, 1)
        XCTAssertFalse(model.faceIDOn)
    }

    func testTurningFaceIDOnAsksForThePasswordThenKeepsIt() async {
        let fake = FakeDevice()
        let model = SettingsModel(account: Fixed.account, service: SettingsService(), auth: SettingsAuth(),
                                  device: fake.device)
        model.setFaceID(true)
        XCTAssertTrue(model.isAskingFaceIDPassword)
        XCTAssertFalse(model.faceIDOn, "nothing is on until a password is kept")
        let on = await model.enableFaceID(password: "hunter22")
        XCTAssertTrue(on)
        XCTAssertEqual(fake.saved?.email, "t@example.com")
        XCTAssertEqual(fake.saved?.password, "hunter22")
        XCTAssertTrue(model.faceIDOn)
        XCTAssertFalse(model.isAskingFaceIDPassword)
    }

    func testAFailedBiometricCheckKeepsNothing() async {
        let fake = FakeDevice()
        fake.passes = false
        let model = SettingsModel(account: Fixed.account, service: SettingsService(), auth: SettingsAuth(),
                                  device: fake.device)
        let on = await model.enableFaceID(password: "hunter22")
        XCTAssertFalse(on)
        XCTAssertNil(fake.saved)
        XCTAssertFalse(model.faceIDOn)
    }
}

// MARK: - Change name

@MainActor
final class ChangeNameModelTests: XCTestCase {
    func testSavesTheTrimmedName() async {
        let log = Log()
        var s = SettingsService()
        s.changeName = { name in
            log.add(name)
            return SettingsAccount(name: name, email: "t@example.com", emailNotifications: true)
        }
        let model = ChangeNameModel(name: "Trevor", service: s)
        XCTAssertFalse(model.canSave, "nothing changed yet")
        model.name = "  Trevor W  "
        XCTAssertTrue(model.canSave)
        let saved = await model.save()
        XCTAssertEqual(log.all, ["Trevor W"])
        XCTAssertEqual(saved?.name, "Trevor W")
    }

    func testANameIsNeeded() async {
        let model = ChangeNameModel(name: "Trevor", service: SettingsService())
        model.name = "   "
        XCTAssertFalse(model.canSave)
        let saved = await model.save()
        XCTAssertNil(saved)
        XCTAssertEqual(model.error, SettingsText.nameEmpty)
    }
}

// MARK: - Change email

@MainActor
final class ChangeEmailModelTests: XCTestCase {
    private func model(_ outcome: EmailChangeOutcome, log: Log = Log(), auth: SettingsAuth = SettingsAuth(),
                       account: SettingsAccount? = nil) -> ChangeEmailModel {
        var s = SettingsService()
        s.startEmailChange = { password, email in
            log.add("start \(password) \(email)")
            return outcome
        }
        s.account = {
            log.add("account")
            if let account { return account }
            throw Down()
        }
        let m = ChangeEmailModel(currentEmail: "t@example.com", service: s, auth: auth)
        m.password = "hunter22"
        m.newEmail = " trevor@caretosher.com "
        return m
    }

    func testSendCodeChecksThePasswordAndMovesToTheCode() async {
        let log = Log()
        let m = model(.sent, log: log)
        await m.sendCode()
        XCTAssertEqual(log.all, ["start hunter22 trevor@caretosher.com"])
        XCTAssertEqual(m.step, .code)
    }

    func testAPasswordThatIsNotRightSaysSoUnderIt() async {
        let m = model(.wrongPassword)
        await m.sendCode()
        XCTAssertEqual(m.step, .address)
        XCTAssertEqual(m.passwordError, SettingsText.incorrectPassword)
    }

    func testAnAddressInUseSaysSoUnderIt() async {
        let m = model(.emailInUse)
        await m.sendCode()
        XCTAssertEqual(m.emailError, SettingsText.emailInUse)
    }

    func testTooManyTriesSaysToTryLater() async {
        let m = model(.tooManyTries)
        await m.sendCode()
        XCTAssertEqual(m.banner, .error(SettingsText.tryLater))
    }

    func testTheCurrentAddressIsNotANewOne() async {
        let log = Log()
        let m = model(.sent, log: log)
        m.newEmail = "T@Example.com"
        await m.sendCode()
        XCTAssertEqual(log.all, [])
        XCTAssertEqual(m.emailError, SettingsText.sameEmail)
    }

    func testAWrongCodeSaysSo() async {
        var auth = SettingsAuth()
        auth.confirmEmail = { _ in throw AuthFailure.codeMismatch }
        let m = model(.sent, auth: auth)
        await m.sendCode()
        m.code = "123456"
        let changed = await m.confirm(from: Fixed.trevor)
        XCTAssertNil(changed)
        XCTAssertEqual(m.codeError, SettingsText.codeIncorrect)
        XCTAssertFalse(m.canSendNewCode)
    }

    func testAnExpiredCodeOffersANewOneWhichIsTheSameRequestAgain() async {
        let log = Log()
        var auth = SettingsAuth()
        auth.confirmEmail = { _ in throw AuthFailure.codeExpired }
        let m = model(.sent, log: log, auth: auth)
        await m.sendCode()
        m.code = "123456"
        _ = await m.confirm(from: Fixed.trevor)
        XCTAssertEqual(m.codeError, SettingsText.codeExpired)
        XCTAssertTrue(m.canSendNewCode)
        await m.sendNewCode()
        XCTAssertEqual(log.all.filter { $0.hasPrefix("start") }.count, 2)
        XCTAssertEqual(m.banner, .info(SettingsText.newCodeSent))
        XCTAssertNil(m.codeError)
        XCTAssertEqual(m.step, .code)
    }

    func testConfirmingRefreshesTheSessionThenReadsTheAccountWithTheNewAddress() async {
        let log = Log()
        var auth = SettingsAuth()
        auth.confirmEmail = { code in log.add("confirm \(code)") }
        auth.forceRefreshSession = { log.add("refresh") }
        let fresh = SettingsAccount(name: "Trevor", email: "trevor@caretosher.com", emailNotifications: true)
        let m = model(.sent, log: log, auth: auth, account: fresh)
        await m.sendCode()
        m.code = "482913"
        let changed = await m.confirm(from: Fixed.trevor)
        XCTAssertEqual(changed, fresh)
        XCTAssertEqual(Array(log.all.dropFirst()), ["confirm 482913", "refresh", "account"])
    }

    func testConfirmedButUnreadStillShowsTheNewAddress() async {
        var auth = SettingsAuth()
        auth.confirmEmail = { _ in }
        auth.forceRefreshSession = { throw Down() }
        let m = model(.sent, auth: auth)
        await m.sendCode()
        m.code = "482913"
        let changed = await m.confirm(from: Fixed.trevor)
        XCTAssertEqual(changed?.email, "trevor@caretosher.com")
        XCTAssertEqual(changed?.name, "Trevor")
    }
}

// MARK: - Change password

@MainActor
final class ChangePasswordModelTests: XCTestCase {
    private func model(_ auth: SettingsAuth, device: FakeDevice = FakeDevice()) -> ChangePasswordModel {
        let m = ChangePasswordModel(email: "t@example.com", auth: auth, device: device.device)
        m.current = "old-pass1"
        m.new = "new-pass1"
        m.confirmNew = "new-pass1"
        return m
    }

    func testTheNewPasswordsMustMatch() async {
        let m = model(SettingsAuth())
        m.confirmNew = "other"
        let outcome = await m.save()
        XCTAssertNil(outcome)
        XCTAssertEqual(m.newError, SettingsText.passwordsDoNotMatch)
    }

    func testACurrentPasswordThatIsNotRightSaysSo() async {
        var auth = SettingsAuth()
        auth.changePassword = { _, _ in throw AuthFailure.incorrectCredentials }
        let m = model(auth)
        let outcome = await m.save()
        XCTAssertNil(outcome)
        XCTAssertEqual(m.currentError, SettingsText.incorrectPassword)
    }

    func testTooManyTriesSaysToTryLater() async {
        var auth = SettingsAuth()
        auth.changePassword = { _, _ in throw AuthFailure.rateLimited }
        let m = model(auth)
        _ = await m.save()
        XCTAssertEqual(m.banner, SettingsText.tryLater)
    }

    func testSavingEndsEverySessionClearsFaceIDAndSignsThisDeviceBackIn() async {
        let log = Log()
        let fake = FakeDevice()
        fake.enabled = true
        var auth = SettingsAuth()
        auth.changePassword = { old, new in log.add("change \(old) \(new)") }
        auth.signOutEverywhere = { log.add("sign out everywhere") }
        auth.signIn = { email, password in
            log.add("sign in \(email) \(password)")
            return true
        }
        let m = model(auth, device: fake)
        let outcome = await m.save()
        XCTAssertEqual(outcome, .changed)
        XCTAssertEqual(log.all, ["change old-pass1 new-pass1", "sign out everywhere",
                                 "sign in t@example.com new-pass1"])
        XCTAssertEqual(fake.disabled, 1, "any password change clears the stored credentials")
    }

    func testIfThisDeviceCannotSignBackInItIsSignedOut() async {
        var auth = SettingsAuth()
        auth.changePassword = { _, _ in }
        auth.signIn = { _, _ in throw Down() }
        let outcome = await model(auth).save()
        XCTAssertEqual(outcome, .signedOut)
    }
}

// MARK: - Send feedback

@MainActor
final class SendFeedbackModelTests: XCTestCase {
    private func model(log: Log, outcome: FeedbackOutcome = .sent) -> SendFeedbackModel {
        var s = SettingsService()
        s.sendFeedback = { draft, anonymous in
            log.add("\(draft.kind.rawValue)|\(draft.message)|\(draft.appVersion)|\(draft.device)|\(anonymous)")
            return outcome
        }
        return SendFeedbackModel(email: "t@example.com", service: s, device: FakeDevice().device)
    }

    func testAKindAndAMessageAreNeeded() {
        let m = model(log: Log())
        XCTAssertFalse(m.anonymous, "off unless turned on")
        XCTAssertFalse(m.canSend)
        m.kind = .bug
        XCTAssertFalse(m.canSend)
        m.message = "  "
        XCTAssertFalse(m.canSend)
        m.message = "It broke"
        XCTAssertTrue(m.canSend)
    }

    func testItGoesWithTheVersionAndDeviceAndSaysAReplyComesByEmail() async {
        let log = Log()
        let m = model(log: log)
        m.kind = .suggestion
        m.message = " Add a dark mode "
        await m.send()
        XCTAssertEqual(log.all, ["suggestion|Add a dark mode|2.0.0 (142)|iPhone18,1, iOS 26.1|false"])
        XCTAssertEqual(m.sent?.anonymous, false)
        XCTAssertEqual(m.sent?.email, "t@example.com")
    }

    func testAnonymousSaysSo() async {
        let log = Log()
        let m = model(log: log)
        m.kind = .other
        m.message = "Hello"
        m.anonymous = true
        await m.send()
        XCTAssertEqual(log.all, ["other|Hello|2.0.0 (142)|iPhone18,1, iOS 26.1|true"])
        XCTAssertEqual(m.sent?.anonymous, true)
    }

    func testTooManyTriesSaysToTryLaterAndKeepsTheMessage() async {
        let m = model(log: Log(), outcome: .tooManyTries)
        m.kind = .bug
        m.message = "It broke"
        await m.send()
        XCTAssertFalse(m.isSent)
        XCTAssertEqual(m.error, SettingsText.tryLater)
        XCTAssertEqual(m.message, "It broke")
    }
}

// MARK: - Close your account

@MainActor
final class CloseAccountModelTests: XCTestCase {
    private func model(_ outcome: CloseAccountOutcome, log: Log = Log()) -> CloseAccountModel {
        var s = SettingsService()
        s.closeAccount = { password in
            log.add(password)
            return outcome
        }
        return CloseAccountModel(service: s)
    }

    func testClosingAsksForThePasswordThenConfirms() {
        let m = model(.closed)
        m.askToClose()
        XCTAssertFalse(m.isConfirming)
        XCTAssertEqual(m.passwordError, SettingsText.enterPassword)
        m.password = "hunter22"
        m.askToClose()
        XCTAssertTrue(m.isConfirming)
        XCTAssertNil(m.passwordError)
    }

    func testCloseAccountSendsThePassword() async {
        let log = Log()
        let m = model(.closed, log: log)
        m.password = "hunter22"
        m.askToClose()
        let closed = await m.close()
        XCTAssertTrue(closed)
        XCTAssertEqual(log.all, ["hunter22"])
    }

    func testAPasswordThatIsNotRightGoesBackAndSaysSo() async {
        let m = model(.wrongPassword)
        m.password = "nope"
        m.askToClose()
        let closed = await m.close()
        XCTAssertFalse(closed)
        XCTAssertFalse(m.isConfirming)
        XCTAssertEqual(m.passwordError, SettingsText.incorrectPassword)
    }

    func testTheOnlyAdminIsRefusedWithEachTeamNamed() async {
        let teams = [SoleAdminTeamInfo(teamID: "riverside", name: "The Riverside Group", alone: false),
                     SoleAdminTeamInfo(teamID: "mine", name: "Just Me", alone: true)]
        let m = model(.soleAdmin(teams))
        m.password = "hunter22"
        let closed = await m.close()
        XCTAssertFalse(closed)
        XCTAssertEqual(m.soleAdminOf, teams)
        XCTAssertEqual(SettingsText.onlyAdminTitle("The Riverside Group"),
                       "You’re the only admin of The Riverside Group")
    }

    func testTooManyTriesSaysToTryLater() async {
        let m = model(.tooManyTries)
        m.password = "x"
        _ = await m.close()
        XCTAssertEqual(m.banner, SettingsText.tryLater)
    }
}

// MARK: - Mapping and the wire

final class SettingsWireTests: XCTestCase {
    private final class FakeToken: TokenProvider {
        func idToken() async throws -> String? { "id-token" }
    }

    /// Keeps every request; answers each with `status` and no body.
    private actor CapturingTransport: ClientTransport {
        let status: HTTPResponse.Status
        private(set) var sent: [(operationID: String, request: HTTPRequest, body: Data?)] = []

        init(status: HTTPResponse.Status) { self.status = status }

        func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
                  operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
            let data: Data? = if let body { try await Data(collecting: body, upTo: 1 << 20) } else { nil }
            sent.append((operationID, request, data))
            guard status.code >= 400 else { return (HTTPResponse(status: status), nil) }
            var fields = HTTPFields()
            fields[.contentType] = "application/json"
            return (HTTPResponse(status: status, headerFields: fields), HTTPBody(#"{"message":"no"}"#))
        }
    }

    private func service(signed: CapturingTransport, anonymous: CapturingTransport) -> SettingsService {
        let url = URL(string: "https://api.example")!
        return .live(APIClient.make(tokenProvider: FakeToken(), serverURL: url, transport: signed),
                     anonymousClient: APIClient.make(tokenProvider: NoTokenProvider(), serverURL: url,
                                                     transport: anonymous))
    }

    func testAnonymousFeedbackGoesWithNoToken() async throws {
        let signed = CapturingTransport(status: .accepted)
        let anonymous = CapturingTransport(status: .accepted)
        let outcome = try await service(signed: signed, anonymous: anonymous).sendFeedback(Fixed.draft, true)
        XCTAssertEqual(outcome, .sent)
        let sentSigned = await signed.sent
        XCTAssertTrue(sentSigned.isEmpty)
        let anonymousSent = await anonymous.sent
        let sent = try XCTUnwrap(anonymousSent.first)
        XCTAssertEqual(sent.operationID, "sendFeedback")
        XCTAssertNil(sent.request.headerFields[.authorization])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "bug")
        XCTAssertEqual(json["app_version"] as? String, "2.0.0 (142)")
        XCTAssertEqual(json["device"] as? String, "iPhone18,1, iOS 26.1")
    }

    func testFeedbackWithTheAccountGoesWithTheToken() async throws {
        let signed = CapturingTransport(status: .accepted)
        let anonymous = CapturingTransport(status: .accepted)
        _ = try await service(signed: signed, anonymous: anonymous).sendFeedback(Fixed.draft, false)
        let signedSent = await signed.sent
        let sent = try XCTUnwrap(signedSent.first)
        XCTAssertEqual(sent.request.headerFields[.authorization], "Bearer id-token")
        let sentAnonymous = await anonymous.sent
        XCTAssertTrue(sentAnonymous.isEmpty)
    }

    func testEmailChangeAnswersMapToOutcomes() async throws {
        for (status, outcome) in [(HTTPResponse.Status.noContent, EmailChangeOutcome.sent),
                                  (.forbidden, .wrongPassword), (.conflict, .emailInUse),
                                  (.tooManyRequests, .tooManyTries)] {
            let t = CapturingTransport(status: status)
            let s = service(signed: t, anonymous: CapturingTransport(status: .accepted))
            let answered = try await s.startEmailChange("pw", "new@example.com")
            XCTAssertEqual(answered, outcome, "\(status)")
        }
    }

    func testTheAccountMapsFromTheCaregiver() {
        let a = SettingsAccount(S.Caregiver(userId: "u", email: "t@example.com", name: "Trevor",
                                            emailNotifications: false))
        XCTAssertEqual(a, SettingsAccount(name: "Trevor", email: "t@example.com", emailNotifications: false))
    }

    func testTheVersionCarriesTheBuild() {
        XCTAssertEqual(SettingsDevice.bundleVersion(["CFBundleShortVersionString": "2.0.0",
                                                     "CFBundleVersion": "142"]), "2.0.0 (142)")
        XCTAssertEqual(SettingsDevice.bundleVersion(["CFBundleShortVersionString": "2.0.0"]), "2.0.0")
    }
}
