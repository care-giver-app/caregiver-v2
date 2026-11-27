import Foundation

/// The words the Settings area shows, kept apart from the views so the models and tests use
/// the same ones (PRD "Settings"; Figma "Settings" page 481:3224).
enum SettingsText {
    static let cancel = "Cancel"
    static let save = "Save"
    static let back = "Back"
    static let done = "Done"

    // MARK: Settings

    static let title = "Settings"
    static let account = "ACCOUNT"
    static let notificationsSection = "NOTIFICATIONS"
    static let app = "APP"
    static let email = "Email"
    static let password = "Password"
    static let notifications = "Notifications"
    static let about = "About this app"
    static let signOut = "Sign out"
    static let closeAccount = "Close your account"
    static let accountFailed = "Couldn't load your account."
    static let emailNotificationsFailed = "Couldn't change email notifications. Try again."

    // MARK: Face ID

    static func faceIDPasswordTitle(_ biometry: String) -> String { "Turn on \(biometry)" }
    static func faceIDPasswordLine(_ biometry: String) -> String {
        "Enter your password to keep it in this iPhone’s keychain, so you can sign back in with \(biometry)."
    }
    static func faceIDReason(_ biometry: String) -> String { "Turn on \(biometry) for CareToSher" }
    static let turnOn = "Turn on"
    static let enterPassword = "Enter your password."

    // MARK: Change name

    static let changeName = "Change name"
    static let yourName = "Your name"
    static let nameEmpty = "Enter your name."

    // MARK: Change email

    static let changeEmail = "Change email"
    static let currentPassword = "Current password"
    static let newEmail = "New email"
    static let sendCode = "Send code"
    static let confirm = "Confirm"
    static let sendNewCode = "Send a new code"
    static let incorrectPassword = "Incorrect password."
    static let emailInUse = "That address is already in use."
    static let sameEmail = "That’s already your email."
    static let notAnEmail = "Enter an email address."
    static let codeIncorrect = "Code is incorrect."
    static let codeExpired = "Code has expired."
    static let newCodeSent = "A new code is on its way."
    static let tryLater = "Too many tries. Wait a little while, then try again."

    static func codeSentTo(_ email: String) -> String { "Code sent to \(email)" }

    // MARK: Change password

    static let changePassword = "Change password"
    static let newPassword = "New password"
    static let confirmNewPassword = "Confirm new password"
    static let passwordsDoNotMatch = "Passwords do not match."
    static let staySignedIn = "You’ll stay signed in on this device. Other devices will be signed out."

    // MARK: Notifications

    static let push = "PUSH"
    static let pushNotifications = "Push notifications"
    static let on = "On"
    static let off = "Off"
    static let openIPhoneSettings = "Open iPhone Settings"
    static let pushOnCaption = "Your iPhone decides this. Change it in iPhone Settings."
    static let pushOffCaption = "Your iPhone is blocking notifications from this app."
    static let emailSection = "EMAIL"
    static let whatEachTeamSends = "WHAT EACH TEAM SENDS"
    static let teamNotificationSettings = "Team notification settings"
    static let teamsCaption = "Each care team chooses its own reminders and alerts in Team."

    static func sentTo(_ email: String) -> String { "Sent to \(email)." }

    // MARK: About this app

    static let appName = "CareToSher"
    static let legal = "LEGAL"
    static let terms = "Terms"
    static let privacy = "Privacy policy"
    static let feedbackAndSupport = "FEEDBACK AND SUPPORT"
    static let sendFeedback = "Send feedback"
    static let contactSupport = "Contact support"
    static let supportAddress = "support@caretosher.com"
    static let termsURL = URL(string: "https://caretosher.com/terms")!
    static let privacyURL = URL(string: "https://caretosher.com/privacy")!
    static let supportURL = URL(string: "mailto:\(supportAddress)")!

    static func version(_ version: String) -> String { "Version \(version)" }

    // MARK: Send feedback

    static let whatKind = "What kind?"
    static let message = "Message"
    /// PRD: About this app — feedback is kept where it is read, so it asks for no care details.
    static let careDetailsWarning = "Please leave out health details and care receivers’ names."
    static let sendAnonymously = "Send anonymously"
    static let send = "Send"
    static let withAccountCaption =
        "Sent with your account so we can reply. Your app version and iPhone model are also included."
    static let anonymousCaption =
        "Your account won’t be attached, so we can’t reply. Your app version and iPhone model are still included."
    static let sentTitle = "Sent, thank you"
    static let sentAnonymously = "Your feedback was submitted anonymously."

    static func followUp(_ email: String) -> String { "If we need to follow up, we’ll email you at \(email)." }

    static func kindName(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: "Bug"
        case .suggestion: "Suggestion"
        case .other: "Something else"
        }
    }

    // MARK: Close your account

    static let closeWhatGoes = "Closing your account removes it, along with your place on every care team you "
        + "belong to. You won’t be able to sign in with it again."
    static let closeWhatStays = "The care you recorded stays. Every entry and journal note you wrote remains "
        + "where it is, so your team keeps the whole record. It will show as written by a former caregiver."
    static let closeMyAccount = "Close my account"
    static let closeThisAccount = "Close this account?"
    static let cannotBeUndone = "This can’t be undone."
    static let closeAccountButton = "Close account"

    static func onlyAdminTitle(_ team: String) -> String { "You’re the only admin of \(team)" }
    static let onlyAdminLine = "Make someone else an admin there before closing your account."
    /// No Figma frame: the PRD's "close that team first, from that care team".
    static func aloneTitle(_ team: String) -> String { "You’re the only one on \(team)" }
    static let aloneLine = "Close that care team first, from Care team on the Team tab, before closing your account."
}
