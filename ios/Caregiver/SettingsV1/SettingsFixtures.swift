#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Trevor (`twilliams0095@gmail.com`), the only
/// admin of The Riverside Group in the refused close, on a phone with Face ID.
@MainActor
enum SettingsFixtures {
    static let trevor = SettingsAccount(name: "Trevor", email: "twilliams0095@gmail.com", emailNotifications: true)

    static func service(account: SettingsAccount = trevor) -> SettingsService {
        var s = SettingsService()
        s.account = { account }
        s.changeName = { name in
            var a = account
            a.name = name
            return a
        }
        s.changeEmailNotifications = { on in
            var a = account
            a.emailNotifications = on
            return a
        }
        s.startEmailChange = { _, _ in .sent }
        s.sendFeedback = { _, _ in .sent }
        s.closeAccount = { _ in .soleAdmin([SoleAdminTeamInfo(teamID: HomeFixtures.riverside.teamID,
                                                              name: HomeFixtures.riverside.name, alone: false)]) }
        return s
    }

    static func device(faceID: Bool = true, push: PushStatus = .on) -> SettingsDevice {
        SettingsDevice(biometryAvailable: { true }, biometryName: { "Face ID" }, authenticate: { _ in true },
                       faceIDEnabled: { faceID }, enableFaceID: { _, _ in }, disableFaceID: {},
                       pushStatus: { push }, appVersion: { "2.0.0 (142)" },
                       deviceDescription: { "iPhone18,1, iOS 26.1" })
    }

    static func model(push: PushStatus = .on) -> SettingsModel {
        SettingsModel(account: TeamFixtures.trevor, service: service(), auth: SettingsAuth(),
                      device: device(push: push))
    }

    /// Close your account, refused: Trevor is the only admin of The Riverside Group.
    static func refusedClose() -> CloseAccountModel {
        let model = CloseAccountModel(service: service())
        model.password = "password1"
        Task { _ = await model.close() }
        return model
    }
}
#endif
