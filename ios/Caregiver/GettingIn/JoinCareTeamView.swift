import SwiftUI

/// Join a care team — the root when a signed-in caregiver belongs to no care team
/// (PRD "Getting into the app"; Figma 358:3354 / 358:3386 / 358:3406 / 497:218 / 497:243).
struct JoinCareTeamView: View {
    let account: Account
    let service: GettingInService
    let onJoined: () async -> Void
    /// `session.signOut()`, run once Sign out? is confirmed.
    let onSignOut: () async -> Void

    @State private var model: JoinCareTeamModel?
    @State private var showCreate = false
    @State private var showSignOut = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showCreate) {
            CreateFirstCareTeamView(service: service, onCreated: onJoined)
        }
        .sheet(isPresented: $showSignOut) {
            SignOutSheet(action: SignOutAction(signOut: onSignOut))
        }
        .task {
            if model == nil {
                let model = JoinCareTeamModel(service: service, onJoined: onJoined)
                self.model = model
                await model.load()
            }
        }
    }

    private func content(_ model: JoinCareTeamModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Figma 497:215 — trailing, styled like Sign in's "Forgot password?".
                HStack {
                    Spacer()
                    Button("Sign out") { showSignOut = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                        .disabled(model.isBusy)
                }
                .padding(.bottom, 18)

                GettingInHeading(title: "Join a care team",
                                 subtitle: "Accept an invitation, or paste an invite code")
                    .padding(.bottom, Theme.Spacing.lg)

                invitations(model)
                    .padding(.bottom, 28)

                StrideSectionHeader(title: "Paste an invite code")
                    .padding(.bottom, 10)
                StrideField(placeholder: "Invite code", icon: "number", text: $model.code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .onSubmit { Task { await model.joinWithCode() } }
                if let error = model.error {
                    StrideAlertBanner(message: error.message)
                        .padding(.top, 10)
                }

                VStack(spacing: 12) {
                    StrideButton(title: "Join", isLoading: model.isJoining) {
                        Task { await model.joinWithCode() }
                    }
                    StrideButton(title: "Create a team instead", style: .secondary) {
                        showCreate = true
                    }
                    .disabled(model.isBusy)
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func invitations(_ model: JoinCareTeamModel) -> some View {
        switch model.invitations {
        case .loading:
            ProgressView()
                .tint(Theme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            // Figma 497:218: saying so, with Try again, where the list goes.
            VStack(alignment: .leading, spacing: 10) {
                StrideAlertBanner(message: JoinCareTeamModel.invitationsFailedMessage)
                StrideButton(title: "Try again", style: .compact) {
                    Task { await model.retry() }
                }
            }
        case .loaded(let invitations) where invitations.isEmpty:
            Text("No invitations are waiting for \(account.email).")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded(let invitations):
            VStack(alignment: .leading, spacing: 0) {
                StrideSectionHeader(title: "Invitations waiting")
                    .padding(.bottom, 10)
                VStack(spacing: 10) {
                    ForEach(invitations) { invitation in
                        StrideInvitationRow(
                            team: invitation.teamName,
                            invitedBy: invitation.invitedByName,
                            isAccepting: model.acceptingCode == invitation.code
                        ) {
                            Task { await model.accept(invitation) }
                        }
                        .disabled(model.isBusy && model.acceptingCode != invitation.code)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Invitations waiting") {
    NavigationStack {
        JoinCareTeamView(account: GettingInFixtures.trevorNoTeam,
                         service: GettingInFixtures.service(),
                         onJoined: {}, onSignOut: {})
    }
}

#Preview("Empty") {
    NavigationStack {
        JoinCareTeamView(account: GettingInFixtures.trevorNoTeam,
                         service: GettingInFixtures.service(invitations: []),
                         onJoined: {}, onSignOut: {})
    }
}

#Preview("Invitations failed") {
    NavigationStack {
        JoinCareTeamView(account: GettingInFixtures.trevorNoTeam,
                         service: GettingInFixtures.service(invitationsFail: true),
                         onJoined: {}, onSignOut: {})
    }
}

#Preview("Rejected code") {
    NavigationStack {
        JoinCareTeamView(account: GettingInFixtures.trevorNoTeam,
                         service: GettingInFixtures.service(redeem: .noLongerValid),
                         onJoined: {}, onSignOut: {})
    }
}
#endif
