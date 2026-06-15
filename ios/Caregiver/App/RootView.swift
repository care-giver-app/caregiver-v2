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
                CreateGroupView(userName: me.userName)
            case .ready(let me):
                mainStack(me)
            }
        }
        .task {
            auth.onSignedIn = { await session.refresh() }
            await session.refresh()
        }
    }

    private func mainStack(_ me: Me) -> some View {
        NavigationStack {
            ReceiversListView(me: me)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .receiver(let r): ReceiverDetailView(me: me, receiver: r)
                    case .tracker(let t): TrackerDetailView(me: me, tracker: t)
                    case .event(let ref): EventDetailView(tracker: ref.tracker, event: ref.event) {}
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Text("Signed in as \(me.userName)")
                            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                        } label: { Image(systemName: "person.circle") }
                    }
                }
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
