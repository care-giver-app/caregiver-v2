import Foundation
import Amplify
import AWSCognitoAuthPlugin
import UIKit
import UserNotifications

/// The Cognito calls Settings makes itself, behind a seam so the models can be tested
/// without Amplify. Every call throws whatever Amplify throws; `AuthFailure.classify`
/// reads it.
struct SettingsAuth: Sendable {
    /// Confirms the new address with the code sent to it.
    var confirmEmail: @Sendable (_ code: String) async throws -> Void = { _ in throw Unstubbed() }
    /// Fetches fresh tokens, so the ID token carries the address just confirmed.
    var forceRefreshSession: @Sendable () async throws -> Void = { throw Unstubbed() }
    var changePassword: @Sendable (_ current: String, _ new: String) async throws -> Void
        = { _, _ in throw Unstubbed() }
    /// Ends every session, this device's included.
    var signOutEverywhere: @Sendable () async -> Void = {}
    /// Signs this device back in; true when it is.
    var signIn: @Sendable (_ email: String, _ password: String) async throws -> Bool = { _, _ in throw Unstubbed() }

    struct Unstubbed: Error {}

    static let amplify = SettingsAuth(
        confirmEmail: { code in
            try await Amplify.Auth.confirm(userAttribute: .email, confirmationCode: code)
        },
        forceRefreshSession: {
            _ = try await Amplify.Auth.fetchAuthSession(options: .forceRefresh())
        },
        changePassword: { current, new in
            try await Amplify.Auth.update(oldPassword: current, to: new)
        },
        signOutEverywhere: {
            _ = await Amplify.Auth.signOut(options: .init(globalSignOut: true))
        },
        signIn: { email, password in
            try await Amplify.Auth.signIn(username: email, password: password).isSignedIn
        }
    )
}

/// Whether the phone lets this app notify (`UNAuthorizationStatus`), as Notifications
/// shows it: the phone's, not a switch the app owns (PRD).
enum PushStatus: Equatable, Sendable {
    case on
    /// Blocked, or never asked: either way nothing arrives.
    case off
}

/// This device's side of Settings: Face ID's saved sign-in, the phone's notification
/// setting, and what the app is running on. Injected for tests and previews.
@MainActor
struct SettingsDevice {
    static let faceIDEnabledKey = "faceIDEnabled"

    var biometryAvailable: () -> Bool = { BiometricAuth.isAvailable }
    var biometryName: () -> String = { BiometricAuth.biometryName }
    var authenticate: (_ reason: String) async -> Bool = { await BiometricAuth.authenticate(reason: $0) }
    /// Face ID is on: switched on, and a password saved for it.
    var faceIDEnabled: () -> Bool = {
        UserDefaults.standard.bool(forKey: SettingsDevice.faceIDEnabledKey) && KeychainStore.credentials() != nil
    }
    /// Saves the password for Face ID and switches it on.
    var enableFaceID: (_ email: String, _ password: String) -> Void = { email, password in
        KeychainStore.save(email: email, password: password)
        UserDefaults.standard.set(true, forKey: SettingsDevice.faceIDEnabledKey)
    }
    /// Switches Face ID off and removes the saved password — what Sign out does too.
    var disableFaceID: () -> Void = { SignOutAction.forgetOnThisDevice() }
    var pushStatus: () async -> PushStatus = {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .on
        default: return .off
        }
    }
    var appVersion: () -> String = { SettingsDevice.bundleVersion() }
    var deviceDescription: () -> String = { SettingsDevice.describeDevice() }

    /// "2.0.0 (142)": the marketing version and the build.
    nonisolated static func bundleVersion(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// "iPhone17,3, iOS 26.1": the hardware model and the system. The model identifier is
    /// the honest one the phone reports; mapping it to a marketing name would need a table
    /// the app would have to keep current.
    static func describeDevice() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        // The simulator reports the Mac's architecture; its model is in the environment.
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        let device = UIDevice.current
        return "\(model), \(device.systemName) \(device.systemVersion)"
    }
}
