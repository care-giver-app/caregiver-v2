import Foundation

enum AppConfig {
    /// The API base URL, injected from the active .xcconfig via Info.plist.
    static var baseURL: URL {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: s) else {
            preconditionFailure("API_BASE_URL missing/invalid in Info.plist")
        }
        return url
    }
}
