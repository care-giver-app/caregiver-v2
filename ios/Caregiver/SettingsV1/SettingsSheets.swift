import SwiftUI

/// Change name (PRD; Figma 482:3423). Save hands the account with its new name to `onSaved`
/// and goes back to Settings.
struct ChangeNameSheet: View {
    @State private var model: ChangeNameModel
    let onSaved: (SettingsAccount) -> Void
    @Environment(\.dismiss) private var dismiss

    init(name: String, service: SettingsService, onSaved: @escaping (SettingsAccount) -> Void) {
        _model = State(initialValue: ChangeNameModel(name: name, service: service))
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        SettingsFormSheet(title: SettingsText.changeName,
                          save: (SettingsText.save, model.canSave, save),
                          isWorking: model.isSaving, detents: [.height(240), .medium]) {
            SettingsInput(label: SettingsText.yourName, text: $model.name, kind: .name)
                .submitLabel(.done)
                .onSubmit(save)
            if let error = model.error {
                StrideAlertBanner(message: error).padding(.top, 10)
            }
        }
    }

    private func save() {
        Task {
            if let account = await model.save() {
                onSaved(account)
                dismiss()
            }
        }
    }
}

/// Change email (PRD; Figma 481:3532 new address, 481:3550 code, 482:3353 password not
/// right, 482:3377 code expired). Confirm hands the account, at its new address, to
/// `onChanged` and goes back to Settings.
struct ChangeEmailSheet: View {
    @State private var model: ChangeEmailModel
    let account: SettingsAccount
    let onChanged: (SettingsAccount) -> Void
    @Environment(\.dismiss) private var dismiss

    init(account: SettingsAccount, service: SettingsService, auth: SettingsAuth,
         model: ChangeEmailModel? = nil, onChanged: @escaping (SettingsAccount) -> Void) {
        _model = State(initialValue: model ?? ChangeEmailModel(currentEmail: account.email, service: service,
                                                               auth: auth))
        self.account = account
        self.onChanged = onChanged
    }

    var body: some View {
        @Bindable var model = model
        SettingsFormSheet(title: SettingsText.changeEmail,
                          leading: model.step == .code ? SettingsText.back : SettingsText.cancel,
                          onLeading: model.step == .code ? { model.backToAddress() } : nil,
                          isWorking: model.isWorking) {
            switch model.step {
            case .address:
                SettingsInput(label: SettingsText.currentPassword, text: $model.password, kind: .password,
                              error: model.passwordError)
                SettingsInput(label: SettingsText.newEmail, text: $model.newEmail, kind: .email,
                              error: model.emailError)
                    .padding(.top, 16)
                banner
                StrideButton(title: SettingsText.sendCode, isLoading: model.isWorking) {
                    Task { await model.sendCode() }
                }
                .disabled(!model.canSendCode && !model.isWorking)
                .padding(.top, 28)
            case .code:
                SettingsInput(label: SettingsText.codeSentTo(model.address), text: $model.code, kind: .code,
                              error: model.codeError)
                if model.canSendNewCode {
                    Button(SettingsText.sendNewCode) { Task { await model.sendNewCode() } }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.top, 6)
                        .disabled(model.isWorking)
                }
                banner
                StrideButton(title: SettingsText.confirm, isLoading: model.isWorking) {
                    Task {
                        if let changed = await model.confirm(from: account) {
                            onChanged(changed)
                            dismiss()
                        }
                    }
                }
                .disabled(!model.canConfirm && !model.isWorking)
                .padding(.top, 28)
            }
        }
    }

    @ViewBuilder private var banner: some View {
        if let banner = model.banner {
            StrideAlertBanner(message: banner.message, tone: banner.tone).padding(.top, 12)
        }
    }
}

/// Change password (PRD; Figma 481:3568, 482:3396 current not right). Save ends every other
/// session and clears the password Face ID keeps, while this device stays signed in.
struct ChangePasswordSheet: View {
    @State private var model: ChangePasswordModel
    let onChanged: (ChangePasswordModel.Outcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(email: String, auth: SettingsAuth, device: SettingsDevice, model: ChangePasswordModel? = nil,
         onChanged: @escaping (ChangePasswordModel.Outcome) -> Void) {
        _model = State(initialValue: model ?? ChangePasswordModel(email: email, auth: auth, device: device))
        self.onChanged = onChanged
    }

    var body: some View {
        @Bindable var model = model
        SettingsFormSheet(title: SettingsText.changePassword,
                          save: (SettingsText.save, model.canSave, save),
                          isWorking: model.isSaving, detents: [.large]) {
            SettingsInput(label: SettingsText.currentPassword, text: $model.current, kind: .password,
                          error: model.currentError)
            SettingsInput(label: SettingsText.newPassword, text: $model.new, kind: .newPassword,
                          error: model.newError)
                .padding(.top, 16)
            SettingsInput(label: SettingsText.confirmNewPassword, text: $model.confirmNew, kind: .newPassword)
                .padding(.top, 16)
            if let banner = model.banner {
                StrideAlertBanner(message: banner).padding(.top, 12)
            }
            SettingsCaption(SettingsText.staySignedIn).padding(.top, 2)
        }
    }

    private func save() {
        Task {
            if let outcome = await model.save() {
                onChanged(outcome)
                dismiss()
            }
        }
    }
}

/// Turning Face ID on: the password to keep for it, then the biometric check. Not a PRD
/// screen of its own — the switch needs a password to store, and after a relaunch the app
/// holds none.
struct FaceIDPasswordSheet: View {
    let model: SettingsModel
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsFormSheet(title: SettingsText.faceIDPasswordTitle(model.biometryName),
                          save: (SettingsText.turnOn, !password.isEmpty, turnOn),
                          isWorking: isWorking, detents: [.height(300), .medium]) {
            Text(SettingsText.faceIDPasswordLine(model.biometryName))
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            SettingsInput(label: SettingsText.password, text: $password, kind: .password, error: error)
                .submitLabel(.done)
                .onSubmit(turnOn)
        }
    }

    private func turnOn() {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        Task {
            if await model.enableFaceID(password: password) {
                dismiss()
            }
            isWorking = false
        }
    }
}

/// Send feedback (PRD; Figma 484:5442, 484:5481 anonymous, 484:5519 sent, 484:5533 sent
/// anonymously). Stays open once sent, saying so; Done goes back to About this app.
struct SendFeedbackSheet: View {
    @State private var model: SendFeedbackModel
    @Environment(\.dismiss) private var dismiss

    init(email: String, service: SettingsService, device: SettingsDevice, model: SendFeedbackModel? = nil) {
        _model = State(initialValue: model ?? SendFeedbackModel(email: email, service: service, device: device))
    }

    var body: some View {
        if let sent = model.sent {
            TeamConfirmation(title: SettingsText.sentTitle,
                             line: sent.anonymous ? SettingsText.sentAnonymously : SettingsText.followUp(sent.email),
                             isWorking: false) {
                TeamTile(icon: "checkmark", tint: Theme.Colors.successTint, size: 48)
                    .foregroundStyle(Theme.Colors.success)
            } buttons: {
                StrideButton(title: SettingsText.done) { dismiss() }
            }
        } else {
            form
        }
    }

    private var form: some View {
        @Bindable var model = model
        return SettingsFormSheet(title: SettingsText.sendFeedback, isWorking: model.isSending,
                                 detents: [.large]) {
            label(SettingsText.whatKind)
            HStack(spacing: 8) {
                ForEach(FeedbackKind.allCases, id: \.self) { kind in
                    StrideChip(label: SettingsText.kindName(kind), isSelected: model.kind == kind) {
                        model.kind = kind
                    }
                }
            }
            label(SettingsText.message).padding(.top, 16)
            TextField("", text: $model.message, axis: .vertical)
                .lineLimit(5...)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
            SettingsRow(icon: nil, label: SettingsText.sendAnonymously) {
                SettingsSwitch(label: SettingsText.sendAnonymously, isOn: $model.anonymous)
            }
            .teamCard()
            .padding(.top, 12)
            SettingsCaption(model.anonymous ? SettingsText.anonymousCaption : SettingsText.withAccountCaption)
            if let error = model.error {
                StrideAlertBanner(message: error).padding(.top, 12)
            }
            StrideButton(title: SettingsText.send, isLoading: model.isSending) {
                Task { await model.send() }
            }
            .disabled(!model.canSend && !model.isSending)
            .padding(.top, 20)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.bottom, 6)
    }
}

/// Close this account? (PRD; Figma 481:3681): the last word before it happens. Close
/// account closes it and lands on Landing; anything refused goes back to Close your account,
/// which says why.
struct CloseThisAccountSheet: View {
    let model: CloseAccountModel
    let onClosed: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TeamConfirmation(title: SettingsText.closeThisAccount, line: SettingsText.cannotBeUndone,
                         isWorking: model.isClosing) {
            TeamTile(icon: "lock", tint: Theme.Colors.alertTint, size: 48)
        } buttons: {
            StrideButton(title: SettingsText.closeAccountButton, style: .destructive, isLoading: model.isClosing) {
                Task {
                    if await model.close() { await onClosed() }
                }
            }
            StrideButton(title: SettingsText.cancel, style: .secondary) { dismiss() }
                .disabled(model.isClosing)
        }
    }
}

#if DEBUG
#Preview("Change name (482:3423)") {
    Color.clear.strideBackground().sheet(isPresented: .constant(true)) {
        ChangeNameSheet(name: "Trevor", service: SettingsFixtures.service()) { _ in }
    }
}

#Preview("Change email (481:3532)") {
    Color.clear.strideBackground().sheet(isPresented: .constant(true)) {
        ChangeEmailSheet(account: SettingsFixtures.trevor, service: SettingsFixtures.service(),
                         auth: SettingsAuth()) { _ in }
    }
}

#Preview("Change password (481:3568)") {
    Color.clear.strideBackground().sheet(isPresented: .constant(true)) {
        ChangePasswordSheet(email: SettingsFixtures.trevor.email, auth: SettingsAuth(),
                            device: SettingsFixtures.device()) { _ in }
    }
}

#Preview("Send feedback (484:5442)") {
    Color.clear.strideBackground().sheet(isPresented: .constant(true)) {
        SendFeedbackSheet(email: SettingsFixtures.trevor.email, service: SettingsFixtures.service(),
                          device: SettingsFixtures.device())
    }
}

#Preview("Close this account? (481:3681)") {
    Color.clear.strideBackground().sheet(isPresented: .constant(true)) {
        CloseThisAccountSheet(model: CloseAccountModel(service: SettingsFixtures.service()), onClosed: {})
    }
}
#endif
