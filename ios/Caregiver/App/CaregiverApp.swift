import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct CaregiverApp: App {
    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            DashboardPlaceholderView() // replaced by RootView in Section D
        }
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
