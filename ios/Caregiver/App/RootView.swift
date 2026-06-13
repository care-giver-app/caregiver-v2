import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var auth = AuthModel()
    @State private var showSignUp = false

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                LoadingView()
            case .signedOut:
                authFlow
            case .onboarding(let me):
                OnboardingPlaceholderView(userName: me.userName)
            case .ready(let me):
                DashboardPlaceholderView(userName: me.userName)
            }
        }
        .task {
            auth.onSignedIn = { await session.refresh() }
            await session.refresh()
        }
    }

    @ViewBuilder private var authFlow: some View {
        if showSignUp {
            SignUpView(model: auth, onSwitchToSignIn: { showSignUp = false })
        } else {
            SignInView(model: auth, onSwitchToSignUp: { showSignUp = true })
        }
    }
}
