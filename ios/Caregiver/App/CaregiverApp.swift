import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct CaregiverApp: App {
    @State private var session = Session()
    @State private var members = MembersStore()

    init() {
        configureAmplify()
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(members)
        }
    }

    private func configureAppearance() {
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.Colors.textTertiary)
    }

    private func configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            #if DEBUG
            let configName = "amplifyconfiguration-dev"
            #else
            let configName = "amplifyconfiguration-prod"
            #endif
            guard let url = Bundle.main.url(forResource: configName, withExtension: "json") else {
                preconditionFailure("\(configName).json missing from bundle")
            }
            let config = try AmplifyConfiguration(configurationFile: url)
            try Amplify.configure(config)
        } catch {
            // In DEBUG, fail loudly so misconfig is caught early.
            assertionFailure("Amplify configure failed: \(error)")
        }
    }
}
