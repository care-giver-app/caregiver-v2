import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var auth = AuthModel()
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage(DeviceSignIn.faceIDOfferedKey) private var faceIDOffered = false
    @State private var showOfferFaceID = false
    @State private var receiverContext = ReceiverContext()
    @State private var summaries = TrackerSummariesModel()
    @State private var selectedTab: StrideTab = .home
    @State private var showQuickLog = false
    @State private var logVersion = 0

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
            case .v1NoTeam(let account):
                NavigationStack {
                    JoinCareTeamView(account: account,
                                     service: .live(session.api),
                                     onJoined: { await session.refresh() },
                                     onSignOut: { await session.signOut() })
                }
                .tint(Theme.Colors.accent)
            case .v1Ready(let account):
                V1PlaceholderView(account: account, onSignOut: { await session.signOut() })
            }
        }
        .task {
            auth.onSignedIn = { await session.refresh() }
            await session.refresh()
        }
        .onChange(of: session.state) {
            switch session.state {
            case .signedOut:
                auth.reset()
                summaries.reset()
                // Never after a deliberate sign out: that is a caregiver saying they want out.
                if !session.signedOutExplicitly && faceIDEnabled && BiometricAuth.isAvailable
                    && auth.hasStoredCredentials {
                    Task {
                        let granted = await BiometricAuth.authenticate(reason: "Sign in to CareToSher")
                        if granted { await auth.signInWithBiometrics() }
                    }
                }
            // `.v1Ready` stands in for Home while flag `v1_api` is on.
            case .ready, .v1Ready:
                if AuthModel.shouldOfferFaceID(biometryAvailable: BiometricAuth.isAvailable,
                                               enabled: faceIDEnabled,
                                               alreadyOffered: faceIDOffered,
                                               hasPassword: auth.hasPasswordInMemory) {
                    faceIDOffered = true
                    showOfferFaceID = true
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showOfferFaceID) {
            OfferFaceIDSheet {
                auth.enableBiometrics()
                faceIDEnabled = true
            }
        }
    }

    private func mainStack(_ me: Me) -> some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(me: me, logVersion: logVersion)
                    .appRouteDestinations(me: me)
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.home)

            NavigationStack {
                InsightsView()
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.insights)

            NavigationStack {
                TeamView()
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.team)

            NavigationStack {
                SettingsView(me: me)
                    .appRouteDestinations(me: me)
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StrideTabBar(selection: $selectedTab) { showQuickLog = true }
        }
        .sheet(isPresented: $showQuickLog) {
            QuickLogWizardView {
                logVersion += 1
                Task {
                    if let id = receiverContext.activeReceiver?.receiverId {
                        await summaries.load(receiverID: id, using: session)
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .environment(receiverContext)
        .environment(summaries)
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
    /// Landing, with Sign in or Sign up pushed over it — never both: they swap —
    /// and the one sheet Getting in raises (PRD "Getting into the app").
    var authFlow: some View {
        @Bindable var auth = auth
        return NavigationStack(path: $auth.path) {
            AuthLandingView(onSignIn: { auth.show(.signIn) },
                            onSignUp: { auth.show(.signUp) })
                .navigationDestination(for: AuthScreen.self) { screen in
                    switch screen {
                    case .signIn: SignInView(model: auth)
                    case .signUp: SignUpView(model: auth)
                    }
                }
        }
        .tint(Theme.Colors.accent)
        .sheet(isPresented: Binding(get: { auth.sheet != nil },
                                    set: { if !$0 { auth.dismissSheet() } })) {
            AuthSheetView(model: auth)
        }
    }
}
