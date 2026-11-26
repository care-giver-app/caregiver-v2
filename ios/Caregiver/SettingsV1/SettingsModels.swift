import Foundation

/// Settings (PRD "Settings"; Figma 481:3226): the caregiver's own account, this device and
/// the app. Nothing on it is about a care receiver or a care team, so it never reloads when
/// either changes.
@MainActor
@Observable
final class SettingsModel {
    /// The caregiver as last known. Seeded from the account the app signed in with, so the
    /// name and address show at once; `GET /v1/me` fills in the rest.
    private(set) var account: SettingsAccount
    /// `GET /v1/me` has answered, so email notifications can be shown and changed.
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    private(set) var isSavingEmailNotifications = false
    private(set) var emailNotificationsFailed = false
    private(set) var faceIDOn: Bool
    private(set) var push: PushStatus?
    /// Turning Face ID on asks for the password to keep for it.
    var isAskingFaceIDPassword = false

    let service: SettingsService
    let auth: SettingsAuth
    let device: SettingsDevice

    init(account: Account, service: SettingsService, auth: SettingsAuth = .amplify,
         device: SettingsDevice = SettingsDevice()) {
        self.account = SettingsAccount(name: account.name, email: account.email, emailNotifications: true)
        self.service = service
        self.auth = auth
        self.device = device
        faceIDOn = device.faceIDEnabled()
    }

    var showsFaceID: Bool { device.biometryAvailable() }
    var biometryName: String { device.biometryName() }

    func load() async {
        faceIDOn = device.faceIDEnabled()
        do {
            account = try await service.account()
            isLoaded = true
            loadFailed = false
        } catch {
            loadFailed = !isLoaded
        }
    }

    func loadPush() async {
        push = await device.pushStatus()
    }

    /// Takes what a sheet changed — a name, an address — as the account now.
    func adopt(_ fresh: SettingsAccount) {
        account = fresh
        isLoaded = true
        loadFailed = false
    }

    /// Off turns Face ID off and removes the saved password at once. On asks for the
    /// password first, since there may be none on this device to keep.
    func setFaceID(_ on: Bool) {
        if on {
            isAskingFaceIDPassword = true
        } else {
            device.disableFaceID()
            faceIDOn = false
        }
    }

    /// Keeps `password` for Face ID once the caregiver has passed the biometric check.
    /// False when the check failed or was cancelled, and Face ID stays off.
    func enableFaceID(password: String) async -> Bool {
        guard !password.isEmpty else { return false }
        guard await device.authenticate(SettingsText.faceIDReason(biometryName)) else { return false }
        device.enableFaceID(account.email, password)
        faceIDOn = device.faceIDEnabled()
        isAskingFaceIDPassword = false
        return true
    }

    /// A password change cleared the saved one (PRD), so the switch reads off.
    func refreshFaceID() {
        faceIDOn = device.faceIDEnabled()
    }

    func setEmailNotifications(_ on: Bool) async {
        guard isLoaded, !isSavingEmailNotifications, on != account.emailNotifications else { return }
        isSavingEmailNotifications = true
        emailNotificationsFailed = false
        defer { isSavingEmailNotifications = false }
        do {
            account = try await service.changeEmailNotifications(on)
        } catch {
            emailNotificationsFailed = true
        }
    }
}

/// Change name (PRD; Figma 482:3423): the name every entry and journal note is signed with.
@MainActor
@Observable
final class ChangeNameModel {
    var name: String
    private(set) var error: String?
    private(set) var isSaving = false

    private let original: String
    private let service: SettingsService

    init(name: String, service: SettingsService) {
        self.name = name
        original = name
        self.service = service
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool { !trimmed.isEmpty && trimmed != original && !isSaving }

    /// The account with its new name, or nil when it was not saved.
    func save() async -> SettingsAccount? {
        guard !isSaving else { return nil }
        guard !trimmed.isEmpty else {
            error = SettingsText.nameEmpty
            return nil
        }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            return try await service.changeName(trimmed)
        } catch let e as AppError {
            error = e.message
        } catch {
            self.error = AppError.unknown.message
        }
        return nil
    }
}

/// Change email (PRD; Figma 481:3532 / 481:3550 / 482:3353 / 482:3377): the current
/// password and the new address, then the code sent to it. The address does not change
/// until the code is confirmed.
@MainActor
@Observable
final class ChangeEmailModel {
    enum Step: Equatable { case address, code }

    var password = ""
    var newEmail = ""
    var code = ""
    private(set) var step: Step = .address
    /// Under the current password.
    private(set) var passwordError: String?
    /// Under the new address.
    private(set) var emailError: String?
    /// Under the code.
    private(set) var codeError: String?
    /// The code expired: offer a new one.
    private(set) var canSendNewCode = false
    /// A line under the form that belongs to no one field.
    private(set) var banner: AuthBanner?
    private(set) var isWorking = false

    private let currentEmail: String
    private let service: SettingsService
    private let auth: SettingsAuth

    init(currentEmail: String, service: SettingsService, auth: SettingsAuth) {
        self.currentEmail = currentEmail
        self.service = service
        self.auth = auth
    }

    var address: String { newEmail.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSendCode: Bool { !password.isEmpty && !address.isEmpty && !isWorking }
    var canConfirm: Bool { code.count == 6 && !isWorking }

    /// Checks the password and sends a code to the new address; moves to the code.
    func sendCode() async {
        guard !isWorking else { return }
        clearErrors()
        guard address.contains("@"), address.contains(".") else {
            emailError = SettingsText.notAnEmail
            return
        }
        guard address.lowercased() != currentEmail.lowercased() else {
            emailError = SettingsText.sameEmail
            return
        }
        if await requestCode() {
            code = ""
            step = .code
        }
    }

    /// Code expired or lost: the same request again sends a new one.
    func sendNewCode() async {
        guard !isWorking else { return }
        clearErrors()
        if await requestCode() {
            code = ""
            banner = .info(SettingsText.newCodeSent)
        } else if step == .code, passwordError != nil || emailError != nil {
            // The password or the address no longer goes through: back to where it is fixed.
            step = .address
        }
    }

    /// Back from the code to the address and password, as typed.
    func backToAddress() {
        clearErrors()
        code = ""
        step = .address
    }

    /// Confirms the code, then refreshes the session so the next request carries the new
    /// address, and reads the account again — the server copies the address from the token.
    /// The account now, or nil when it was not confirmed.
    func confirm(from known: SettingsAccount) async -> SettingsAccount? {
        guard !isWorking else { return nil }
        clearErrors()
        guard code.count == 6 else {
            codeError = SettingsText.codeIncorrect
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.confirmEmail(code)
        } catch {
            switch AuthFailure.classify(error) {
            case .codeMismatch: codeError = SettingsText.codeIncorrect
            case .codeExpired:
                codeError = SettingsText.codeExpired
                canSendNewCode = true
            case .rateLimited, .locked: banner = .error(SettingsText.tryLater)
            case .network: banner = .error(AppError.transport.message)
            default: banner = .error(AppError.unknown.message)
            }
            return nil
        }
        // Confirmed: the change is made whatever happens next. A refresh or read that fails
        // only leaves the old address on screen until Settings next loads.
        try? await auth.forceRefreshSession()
        let fresh = try? await service.account()
        if let fresh { return fresh }
        var changed = known
        changed.email = address
        return changed
    }

    private func requestCode() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await service.startEmailChange(password, address) {
            case .sent: return true
            case .wrongPassword: passwordError = SettingsText.incorrectPassword
            case .emailInUse: emailError = SettingsText.emailInUse
            case .tooManyTries: banner = .error(SettingsText.tryLater)
            case .rejected(let message): emailError = message ?? SettingsText.notAnEmail
            }
        } catch let e as AppError {
            banner = .error(e.message)
        } catch {
            banner = .error(AppError.unknown.message)
        }
        return false
    }

    private func clearErrors() {
        passwordError = nil
        emailError = nil
        codeError = nil
        canSendNewCode = false
        banner = nil
    }
}

/// Change password (PRD; Figma 481:3568 / 482:3396). Saving ends every other session and
/// clears the password Face ID keeps, while this device stays signed in.
@MainActor
@Observable
final class ChangePasswordModel {
    enum Outcome: Equatable {
        case changed
        /// Changed, but signing this device back in failed: it is signed out.
        case signedOut
    }

    var current = ""
    var new = ""
    var confirmNew = ""
    private(set) var currentError: String?
    private(set) var newError: String?
    private(set) var banner: String?
    private(set) var isSaving = false

    private let email: String
    private let auth: SettingsAuth
    private let device: SettingsDevice

    init(email: String, auth: SettingsAuth, device: SettingsDevice) {
        self.email = email
        self.auth = auth
        self.device = device
    }

    var canSave: Bool { !current.isEmpty && !new.isEmpty && !confirmNew.isEmpty && !isSaving }

    func save() async -> Outcome? {
        guard !isSaving else { return nil }
        currentError = nil
        newError = nil
        banner = nil
        guard new == confirmNew else {
            newError = SettingsText.passwordsDoNotMatch
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await auth.changePassword(current, new)
        } catch {
            switch AuthFailure.classify(error) {
            case .incorrectCredentials: currentError = SettingsText.incorrectPassword
            case .locked, .rateLimited: banner = SettingsText.tryLater
            case .invalidPassword: newError = AuthModel.Copy.invalidPassword
            case .network: banner = AppError.transport.message
            default: banner = AppError.unknown.message
            }
            return nil
        }
        // Any password change clears the stored credentials (PRD).
        device.disableFaceID()
        // Every other session ends — this one with them — and this device signs back in.
        await auth.signOutEverywhere()
        let signedIn = (try? await auth.signIn(email, new)) ?? false
        return signedIn ? .changed : .signedOut
    }
}

/// Send feedback (PRD; Figma 484:5442 / 484:5481 / 484:5519 / 484:5533). Nothing sent is
/// kept in the app.
@MainActor
@Observable
final class SendFeedbackModel {
    var kind: FeedbackKind?
    var message = ""
    /// Off unless turned on (PRD).
    var anonymous = false
    /// Sent: the sheet says so, and how a reply would come.
    private(set) var sent: (anonymous: Bool, email: String)?
    private(set) var error: String?
    private(set) var isSending = false

    private let email: String
    private let service: SettingsService
    private let device: SettingsDevice

    init(email: String, service: SettingsService, device: SettingsDevice) {
        self.email = email
        self.service = service
        self.device = device
    }

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSend: Bool { kind != nil && !trimmed.isEmpty && !isSending }
    var isSent: Bool { sent != nil }

    func send() async {
        guard !isSending, sent == nil, let kind, !trimmed.isEmpty else { return }
        isSending = true
        error = nil
        defer { isSending = false }
        let draft = FeedbackDraft(kind: kind, message: String(trimmed.prefix(5000)),
                                  appVersion: String(device.appVersion().prefix(50)),
                                  device: String(device.deviceDescription().prefix(100)))
        do {
            switch try await service.sendFeedback(draft, anonymous) {
            case .sent: sent = (anonymous, email)
            case .tooManyTries: error = SettingsText.tryLater
            case .rejected(let message): error = message ?? AppError.unknown.message
            }
        } catch let e as AppError {
            error = e.message
        } catch {
            self.error = AppError.unknown.message
        }
    }
}

/// Close your account (PRD; Figma 481:3613 / 481:3645 / 481:3681): what goes and what
/// stays, the password, then Close this account? before anything happens.
@MainActor
@Observable
final class CloseAccountModel {
    var password = ""
    var isConfirming = false
    private(set) var passwordError: String?
    private(set) var banner: String?
    /// The care teams that refused it: promote someone first, or close the team first.
    private(set) var soleAdminOf: [SoleAdminTeamInfo] = []
    private(set) var isClosing = false

    private let service: SettingsService

    init(service: SettingsService) {
        self.service = service
    }

    /// Close my account: asks Close this account? once there is a password to send.
    func askToClose() {
        passwordError = nil
        banner = nil
        guard !password.isEmpty else {
            passwordError = SettingsText.enterPassword
            return
        }
        isConfirming = true
    }

    /// Close account. True when the account is closed; otherwise Close this account? goes
    /// and the screen says why.
    func close() async -> Bool {
        guard !isClosing else { return false }
        isClosing = true
        defer { isClosing = false }
        passwordError = nil
        banner = nil
        soleAdminOf = []
        do {
            switch try await service.closeAccount(password) {
            case .closed:
                return true
            case .wrongPassword:
                passwordError = SettingsText.incorrectPassword
            case .tooManyTries:
                banner = SettingsText.tryLater
            case .soleAdmin(let teams):
                soleAdminOf = teams
            }
        } catch let e as AppError {
            banner = e.message
        } catch {
            banner = AppError.unknown.message
        }
        isConfirming = false
        return false
    }
}
