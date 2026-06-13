import Foundation
import Amplify
import AWSPluginsCore

/// Pulls the current Cognito ID token from Amplify for the auth middleware.
struct CognitoTokenProvider: TokenProvider {
    func idToken() async throws -> String? {
        let session = try await Amplify.Auth.fetchAuthSession()
        guard let provider = session as? AuthCognitoTokensProvider else { return nil }
        switch provider.getCognitoTokens() {
        case .success(let tokens): return tokens.idToken
        case .failure: return nil
        }
    }
}
