import SwiftUI

/// Every screen pushed on the Settings tab's own stack (PRD: Notifications, About this app
/// and Close your account are pushes).
enum SettingsRoute: Hashable {
    case notifications, about, closeAccount
}

/// The sheets Settings raises itself (PRD: Change name, Change email, Change password and
/// Sign out? are sheets). Turning Face ID on asks for the password in one too.
enum SettingsSheet: String, Identifiable {
    case changeName, changeEmail, changePassword, signOut, faceIDPassword
    var id: String { rawValue }
}

/// The Settings tab on the `/v1` path: Settings at the root of its own stack, with the
/// screens it pushes. `onSignOut` lands on Landing; `onTeamNotifications` switches to Team.
struct SettingsTabV1: View {
    let model: SettingsModel
    let onSignOut: () async -> Void
    let onTeamNotifications: () -> Void

    @State private var path: [SettingsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsV1View(model: model, onSignOut: onSignOut)
                .navigationDestination(for: SettingsRoute.self) { route in
                    Group {
                        switch route {
                        case .notifications:
                            SettingsNotificationsV1View(model: model, onTeamNotifications: onTeamNotifications)
                        case .about:
                            AboutAppV1View(model: model)
                        case .closeAccount:
                            CloseAccountV1View(service: model.service) {
                                // Closed: nothing left on this device for Face ID, and Landing.
                                await SignOutAction(signOut: onSignOut)()
                            }
                        }
                    }
                    // Pushed screens don't inherit the stack's inset, so each clears the bar itself.
                    .strideTabBarClearance()
                }
                .strideTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

/// Settings (PRD "Settings"; Figma 481:3226): your name and address, Email, Password and
/// Face ID; Notifications; About this app; Sign out; and Close your account.
struct SettingsV1View: View {
    let model: SettingsModel
    let onSignOut: () async -> Void

    @State private var sheet: SettingsSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(SettingsText.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 20)
                if model.loadFailed {
                    StrideAlertBanner(message: SettingsText.accountFailed).padding(.bottom, 12)
                }
                profile.padding(.bottom, 22)

                TeamSectionLabel(SettingsText.account)
                VStack(spacing: 0) {
                    SettingsButtonRow { sheet = .changeEmail } label: {
                        SettingsRow(icon: "envelope", label: SettingsText.email)
                    }
                    TeamRowDivider(inset: 56)
                    SettingsButtonRow { sheet = .changePassword } label: {
                        SettingsRow(icon: "lock", label: SettingsText.password)
                    }
                    if model.showsFaceID {
                        TeamRowDivider(inset: 56)
                        SettingsRow(icon: model.biometryName == "Face ID" ? "faceid" : "touchid",
                                    label: model.biometryName) {
                            SettingsSwitch(label: model.biometryName,
                                           isOn: Binding(get: { model.faceIDOn }, set: { model.setFaceID($0) }))
                        }
                    }
                }
                .teamCard()
                .padding(.bottom, 22)

                TeamSectionLabel(SettingsText.notificationsSection)
                NavigationLink(value: SettingsRoute.notifications) {
                    SettingsRow(icon: "bell", label: SettingsText.notifications)
                }
                .buttonStyle(.plain)
                .teamCard()
                .padding(.bottom, 22)

                TeamSectionLabel(SettingsText.app)
                NavigationLink(value: SettingsRoute.about) {
                    SettingsRow(icon: "info.circle", label: SettingsText.about)
                }
                .buttonStyle(.plain)
                .teamCard()
                .padding(.bottom, 22)

                SettingsButtonRow { sheet = .signOut } label: {
                    SettingsRow(icon: "rectangle.portrait.and.arrow.right", label: SettingsText.signOut) {
                        EmptyView()
                    }
                }
                .teamCard()
                .padding(.bottom, 10)

                NavigationLink(value: SettingsRoute.closeAccount) {
                    SettingsRow(icon: nil, label: SettingsText.closeAccount, labelColor: Theme.Colors.alert) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                .teamCard()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .changeName:
                ChangeNameSheet(name: model.account.name, service: model.service) { model.adopt($0) }
            case .changeEmail:
                ChangeEmailSheet(account: model.account, service: model.service, auth: model.auth) {
                    model.adopt($0)
                }
            case .changePassword:
                ChangePasswordSheet(email: model.account.email, auth: model.auth, device: model.device) { outcome in
                    model.refreshFaceID()
                    if outcome == .signedOut { Task { await onSignOut() } }
                }
            case .signOut:
                SignOutSheet(action: SignOutAction(signOut: onSignOut))
            case .faceIDPassword:
                FaceIDPasswordSheet(model: model)
            }
        }
        .onChange(of: model.isAskingFaceIDPassword) { _, asking in
            if asking { sheet = .faceIDPassword }
        }
        .onChange(of: sheet) { _, now in
            if now == nil { model.isAskingFaceIDPassword = false }
        }
    }

    /// Your name and address; the name is yours to change (Figma "Profile").
    private var profile: some View {
        Button { sheet = .changeName } label: {
            HStack(spacing: 14) {
                TeamMonogram(name: model.account.name, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.account.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(model.account.email)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                TeamChevron()
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .teamCard()
        .accessibilityHint(SettingsText.changeName)
    }
}

/// Notifications (PRD; Figma 481:3346 push on, 481:3405 push off): the channels only —
/// push as the phone has it, email on or off — and a way to what each team sends.
struct SettingsNotificationsV1View: View {
    let model: SettingsModel
    let onTeamNotifications: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TeamSectionLabel(SettingsText.push)
                VStack(spacing: 0) {
                    SettingsRow(icon: "bell", label: SettingsText.pushNotifications) {
                        switch model.push {
                        case .on:
                            Text(SettingsText.on).font(.system(size: 14)).foregroundStyle(Theme.Colors.accent)
                        case .off:
                            Text(SettingsText.off).font(.system(size: 14)).foregroundStyle(Theme.Colors.alert)
                        case nil:
                            EmptyView()
                        }
                    }
                    if model.push == .off {
                        TeamRowDivider(inset: 16)
                        SettingsButtonRow {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        } label: {
                            SettingsRow(icon: nil, label: SettingsText.openIPhoneSettings,
                                        labelColor: Theme.Colors.accent)
                        }
                    }
                }
                .teamCard()
                if let push = model.push {
                    SettingsCaption(push == .on ? SettingsText.pushOnCaption : SettingsText.pushOffCaption)
                }

                TeamSectionLabel(SettingsText.emailSection).padding(.top, 22)
                SettingsRow(icon: "envelope", label: SettingsText.email) {
                    SettingsSwitch(label: SettingsText.email,
                                   isOn: Binding(get: { model.account.emailNotifications },
                                                 set: { on in Task { await model.setEmailNotifications(on) } }))
                        .disabled(!model.isLoaded || model.isSavingEmailNotifications)
                }
                .teamCard()
                if model.emailNotificationsFailed {
                    StrideAlertBanner(message: SettingsText.emailNotificationsFailed).padding(.top, 8)
                }
                SettingsCaption(SettingsText.sentTo(model.account.email))

                TeamSectionLabel(SettingsText.whatEachTeamSends).padding(.top, 22)
                SettingsButtonRow(action: onTeamNotifications) {
                    SettingsRow(icon: nil, label: SettingsText.teamNotificationSettings)
                }
                .teamCard()
                SettingsCaption(SettingsText.teamsCaption)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 32)
        }
        .settingsPushedScreen(SettingsText.notifications)
        .task {
            await model.loadPush()
            if !model.isLoaded { await model.load() }
        }
        // Back from iPhone Settings: show what the phone says now.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.loadPush() } }
        }
    }
}

/// About this app (PRD; Figma 481:3474): the version, the terms and the privacy policy on
/// the web, Send feedback, and the support address as text with a tap to the mail app.
struct AboutAppV1View: View {
    let model: SettingsModel

    @State private var isSendingFeedback = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 6) {
                    // Figma's 64pt icon tile; the app's mark on it, since the app icon
                    // itself cannot be drawn from the asset catalog.
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .frame(width: 64, height: 64)
                        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
                        .accessibilityHidden(true)
                        .padding(.bottom, 6)
                    Text(SettingsText.appName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(SettingsText.version(model.device.appVersion()))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.bottom, 22)

                TeamSectionLabel(SettingsText.legal)
                VStack(spacing: 0) {
                    SettingsButtonRow { openURL(SettingsText.termsURL) } label: {
                        SettingsRow(icon: "doc.text", label: SettingsText.terms)
                    }
                    TeamRowDivider(inset: 56)
                    SettingsButtonRow { openURL(SettingsText.privacyURL) } label: {
                        SettingsRow(icon: "shield", label: SettingsText.privacy)
                    }
                }
                .teamCard()

                TeamSectionLabel(SettingsText.feedbackAndSupport).padding(.top, 22)
                VStack(spacing: 0) {
                    SettingsButtonRow { isSendingFeedback = true } label: {
                        SettingsRow(icon: "pencil", label: SettingsText.sendFeedback)
                    }
                    TeamRowDivider(inset: 56)
                    SettingsButtonRow { openURL(SettingsText.supportURL) } label: {
                        SettingsRow(icon: "questionmark.circle", label: SettingsText.contactSupport)
                    }
                }
                .teamCard()
                // Shown, not only offered: a phone with no mail app set up does nothing on the tap.
                Text(SettingsText.supportAddress)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textSelection(.enabled)
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 32)
        }
        .settingsPushedScreen(SettingsText.about)
        .sheet(isPresented: $isSendingFeedback) {
            SendFeedbackSheet(email: model.account.email, service: model.service, device: model.device)
        }
    }
}

/// Close your account (PRD; Figma 481:3613, 481:3645 only admin): what goes and what stays,
/// the password, and Close my account — which asks Close this account? first.
struct CloseAccountV1View: View {
    @State private var model: CloseAccountModel
    let onClosed: () async -> Void

    init(service: SettingsService, model: CloseAccountModel? = nil, onClosed: @escaping () async -> Void) {
        _model = State(initialValue: model ?? CloseAccountModel(service: service))
        self.onClosed = onClosed
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.soleAdminOf) { team in
                    refusal(team).padding(.bottom, 12)
                }
                if !model.soleAdminOf.isEmpty { Spacer().frame(height: 8) }
                if let banner = model.banner {
                    StrideAlertBanner(message: banner).padding(.bottom, 20)
                }
                paragraph(SettingsText.closeWhatGoes)
                paragraph(SettingsText.closeWhatStays).padding(.top, 14)
                SettingsInput(label: SettingsText.password, text: $model.password, kind: .password,
                              error: model.passwordError)
                    .padding(.top, 22)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StrideButton(title: SettingsText.closeMyAccount, style: .destructive) { model.askToClose() }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
        }
        .settingsPushedScreen(SettingsText.closeAccount)
        .sheet(isPresented: $model.isConfirming) {
            CloseThisAccountSheet(model: model, onClosed: onClosed)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A team that refuses it, named, with what to do there first (Figma 481:3658 "Callout").
    private func refusal(_ team: SoleAdminTeamInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(team.alone ? SettingsText.aloneTitle(team.name) : SettingsText.onlyAdminTitle(team.name))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.alert)
            Text(team.alone ? SettingsText.aloneLine : SettingsText.onlyAdminLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 12).fill(Theme.Colors.alertTint) }
    }
}

#if DEBUG
#Preview("Settings (481:3226)") {
    SettingsTabV1(model: SettingsFixtures.model(), onSignOut: {}, onTeamNotifications: {})
}

#Preview("Notifications, push on (481:3346)") {
    NavigationStack {
        SettingsNotificationsV1View(model: SettingsFixtures.model(push: .on), onTeamNotifications: {})
    }
}

#Preview("Notifications, push off (481:3405)") {
    NavigationStack {
        SettingsNotificationsV1View(model: SettingsFixtures.model(push: .off), onTeamNotifications: {})
    }
}

#Preview("About this app (481:3474)") {
    NavigationStack { AboutAppV1View(model: SettingsFixtures.model()) }
}

#Preview("Close your account (481:3613)") {
    NavigationStack { CloseAccountV1View(service: SettingsFixtures.service(), onClosed: {}) }
}

#Preview("Close your account, only admin (481:3645)") {
    NavigationStack {
        CloseAccountV1View(service: SettingsFixtures.service(),
                           model: SettingsFixtures.refusedClose(), onClosed: {})
    }
}
#endif
