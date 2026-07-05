import SwiftUI

enum AuthScreen { case landing, signIn, signUp }

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var auth = AuthModel()
    @State private var authScreen: AuthScreen = .landing
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var showEnableFaceID = false
    @State private var receiverContext = ReceiverContext()

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                StrideLoadingView()
            case .signedOut:
                authFlow
            case .onboarding(let me):
                CreateGroupView(userName: me.userName)
            case .ready(let me):
                mainStack(me)
            }
        }
        .task {
            auth.onSignedIn = { await session.refresh() }
            await session.refresh()
        }
        .onChange(of: session.state) {
            switch session.state {
            case .signedOut:
                authScreen = .landing
                if !session.signedOutExplicitly && faceIDEnabled && BiometricAuth.isAvailable {
                    Task {
                        let granted = await BiometricAuth.authenticate(reason: "Sign in to Caregiver")
                        if granted { await auth.signInWithBiometrics() }
                    }
                }
            case .ready:
                if BiometricAuth.isAvailable && !faceIDEnabled {
                    showEnableFaceID = true
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showEnableFaceID) {
            EnableBiometricSheet {
                auth.enableBiometrics()
                faceIDEnabled = true
            }
        }
    }

    private func mainStack(_ me: Me) -> some View {
        TabView {
            NavigationStack {
                HomeView(me: me)
                    .appRouteDestinations(me: me)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "list.bullet.clipboard") }

            NavigationStack {
                SettingsView(me: me)
                    .appRouteDestinations(me: me)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.Colors.accent)
        .environment(receiverContext)
        .task { await receiverContext.load(using: session) }
    }

}

private extension View {
    /// The app's shared `Route` destinations, applied to any `NavigationStack`
    /// that needs to push receiver / tracker / event screens.
    func appRouteDestinations(me: Me) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .receiver(let r): ReceiverDetailView(me: me, receiver: r)
            case .tracker(let t): TrackerDetailView(me: me, tracker: t)
            case .event(let ref): EventDetailView(tracker: ref.tracker, event: ref.event) {}
            }
        }
    }
}

// MARK: - Auth flow
private extension RootView {
    @ViewBuilder var authFlow: some View {
        switch authScreen {
        case .landing:
            AuthLandingView(
                onSignIn: { authScreen = .signIn },
                onSignUp: { authScreen = .signUp }
            )
        case .signIn:
            SignInView(model: auth, onCreateAccount: { authScreen = .signUp })
        case .signUp:
            SignUpView(model: auth, onSignIn: { authScreen = .signIn })
        }
    }
}
