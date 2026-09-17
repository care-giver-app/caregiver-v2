import Foundation
import Amplify
import AWSPluginsCore

/// Reads — and when necessary clears — whatever session Amplify holds locally.
protocol AuthSessionReconciling: Sendable {
    func localState() async -> LocalSessionState
    func clearLocalSession() async
}

struct AmplifyAuthSessionReconciler: AuthSessionReconciling {
    func localState() async -> LocalSessionState {
        let session: AuthSession
        do {
            session = try await Amplify.Auth.fetchAuthSession()
        } catch let error as AuthError {
            return LocalSessionState.classify(tokenFailure: error)
        } catch {
            return .expired
        }

        guard session.isSignedIn else { return .none }
        guard let tokens = session as? AuthCognitoTokensProvider else { return .expired }

        switch tokens.getCognitoTokens() {
        case .success:
            let username = try? await Amplify.Auth.getCurrentUser().username
            return .valid(username: username ?? "")
        case .failure(let error):
            return LocalSessionState.classify(tokenFailure: error)
        }
    }

    func clearLocalSession() async {
        _ = await Amplify.Auth.signOut()
    }
}
