import SwiftUI

/// A Team-area form sheet (Figma 450:3519 / 450:3537 / 450:3844): Cancel and the title in
/// its bar, the inputs, then its one action.
private struct TeamFormSheet<Content: View>: View {
    let title: String
    let isWorking: Bool
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Colors.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TeamText.cancel) { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
    }
}

/// Create a care team (PRD; Figma 450:3519). Create team hands the new team to `onCreated`
/// and goes back to Team, where it is now a row.
struct CreateCareTeamSheet: View {
    @State private var model: CreateCareTeamModel
    let onCreated: (Account.Team) -> Void
    @Environment(\.dismiss) private var dismiss

    init(service: TeamService, onCreated: @escaping (Account.Team) -> Void) {
        _model = State(initialValue: CreateCareTeamModel(service: service))
        self.onCreated = onCreated
    }

    var body: some View {
        @Bindable var model = model
        TeamFormSheet(title: TeamText.newTeamTitle, isWorking: model.isCreating) {
            TeamLabeledInput(label: TeamText.teamName) {
                TextField("", text: $model.name)
                    .textContentType(.organizationName)
                    .submitLabel(.done)
                    .onSubmit(create)
            }
            if let error = model.error {
                StrideAlertBanner(message: error).padding(.top, 10)
            }
            StrideButton(title: TeamText.createTeamButton, isLoading: model.isCreating, action: create)
                .disabled(!model.canCreate && !model.isCreating)
                .padding(.top, 28)
        }
    }

    private func create() {
        Task {
            if let team = await model.create() {
                onCreated(team)
                dismiss()
            }
        }
    }
}

/// Add care receiver (PRD; Figma 450:3537): name and time zone. Add receiver hands the new
/// receiver to `onAdded`, which lands on their Home.
struct AddCareReceiverSheet: View {
    @State private var model: AddCareReceiverModel
    let onAdded: (TeamReceiver) -> Void
    @Environment(\.dismiss) private var dismiss

    init(team: Account.Team, service: TeamService, onAdded: @escaping (TeamReceiver) -> Void) {
        _model = State(initialValue: AddCareReceiverModel(team: team, service: service))
        self.onAdded = onAdded
    }

    var body: some View {
        @Bindable var model = model
        TeamFormSheet(title: TeamText.newReceiverTitle, isWorking: model.isAdding) {
            TeamLabeledInput(label: TeamText.name) {
                TextField("", text: $model.name)
                    .textContentType(.name)
                    .submitLabel(.done)
            }
            TeamLabeledInput(label: TeamText.timeZone) {
                Menu {
                    Picker(TeamText.timeZone, selection: $model.zone) {
                        ForEach(model.zones, id: \.identifier) { zone in
                            Text(AddCareReceiverModel.label(zone)).tag(zone)
                        }
                    }
                } label: {
                    HStack {
                        Text(AddCareReceiverModel.label(model.zone))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                }
            }
            .padding(.top, 16)
            if let error = model.error {
                StrideAlertBanner(message: error).padding(.top, 10)
            }
            StrideButton(title: TeamText.addReceiverButton, isLoading: model.isAdding) {
                Task {
                    if let receiver = await model.add() {
                        onAdded(receiver)
                        dismiss()
                    }
                }
            }
            .disabled(!model.canAdd && !model.isAdding)
            .padding(.top, 20)
        }
    }
}

/// Invite a caregiver (PRD; Figma 450:3844): an email address. Create invitation hands the
/// invitation to `onCreated` and goes back to Care team, where its code waits to be copied.
struct InviteCaregiverSheet: View {
    @State private var model: InviteCaregiverModel
    let onCreated: (TeamInvitationInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    init(teamID: String, service: TeamService, onCreated: @escaping (TeamInvitationInfo) -> Void) {
        _model = State(initialValue: InviteCaregiverModel(teamID: teamID, service: service))
        self.onCreated = onCreated
    }

    var body: some View {
        @Bindable var model = model
        TeamFormSheet(title: TeamText.inviteCaregiver, isWorking: model.isCreating) {
            TeamLabeledInput(label: TeamText.emailAddress) {
                TextField("", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            Text(TeamText.inviteExplainer)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let error = model.error {
                StrideAlertBanner(message: error).padding(.top, 10)
            }
            StrideButton(title: TeamText.createInvitation, isLoading: model.isCreating) {
                Task {
                    if let invitation = await model.create() {
                        onCreated(invitation)
                        dismiss()
                    }
                }
            }
            .disabled(!model.canCreate && !model.isCreating)
            .padding(.top, 20)
        }
    }
}

/// A caregiver (PRD; Figma 450:3864): their name and role, then Make admin or Make
/// caregiver, and Remove from this care team. `onChanged` runs once one is done, just
/// before the sheet goes back to Care team.
struct MemberActionsSheet: View {
    @State private var model: MemberActionsModel
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: MemberActionsModel, onChanged: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onChanged = onChanged
    }

    var body: some View {
        TeamConfirmation(title: model.member.name,
                         line: TeamText.memberLine(model.member.role, team: model.teamName),
                         failure: model.refusal, isWorking: model.working != nil) {
            TeamMonogram(name: model.member.name, size: 48)
        } buttons: {
            StrideButton(title: model.roleAction == .makeAdmin ? TeamText.makeAdmin : TeamText.makeCaregiver,
                         style: .secondary) { perform(model.roleAction) }
                .disabled(model.working != nil)
            StrideButton(title: TeamText.remove, style: .destructive, isLoading: model.working == .remove) {
                perform(.remove)
            }
            .disabled(model.working != nil && model.working != .remove)
            StrideButton(title: TeamText.cancel, style: .secondary) { dismiss() }
                .disabled(model.working != nil)
        }
    }

    private func perform(_ action: MemberActionsModel.Action) {
        Task {
            if await model.perform(action) {
                onChanged()
                dismiss()
            }
        }
    }
}

/// Leave this care team? or Close this care team? (PRD; Figma 450:3886). `onOutcome`
/// hears how it went just before the sheet goes.
struct LeaveTeamSheet: View {
    @State private var model: LeaveTeamModel
    let onOutcome: (LeaveTeamModel.Outcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: LeaveTeamModel, onOutcome: @escaping (LeaveTeamModel.Outcome) -> Void) {
        _model = State(initialValue: model)
        self.onOutcome = onOutcome
    }

    private var isLeave: Bool { model.kind == .leave }

    var body: some View {
        TeamConfirmation(title: isLeave ? TeamText.leaveTitle : TeamText.closeTitle,
                         line: isLeave ? TeamText.leaveLine : TeamText.closeLine,
                         failure: model.failure, isWorking: model.isWorking) {
            TeamTile(size: 48)
        } buttons: {
            StrideButton(title: isLeave ? TeamText.leaveButton : TeamText.closeButton, style: .destructive,
                         isLoading: model.isWorking) {
                Task {
                    if let outcome = await model.confirm() {
                        onOutcome(outcome)
                        dismiss()
                    }
                }
            }
            StrideButton(title: TeamText.cancel, style: .secondary) { dismiss() }
                .disabled(model.isWorking)
        }
    }
}

#if DEBUG
#Preview("Create a care team (450:3519)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateCareTeamSheet(service: TeamFixtures.service()) { _ in }
    }
}

#Preview("Add care receiver (450:3537)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddCareReceiverSheet(team: TeamFixtures.riverside, service: TeamFixtures.service()) { _ in }
    }
}

#Preview("Invite a caregiver (450:3844)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        InviteCaregiverSheet(teamID: TeamFixtures.riverside.teamID, service: TeamFixtures.service()) { _ in }
    }
}

#Preview("A caregiver (450:3864)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MemberActionsSheet(model: MemberActionsModel(member: TeamFixtures.dana, teamID: TeamFixtures.riverside.teamID,
                                                     teamName: TeamFixtures.riverside.name, isOnlyAdmin: false,
                                                     service: TeamFixtures.service())) {}
    }
}

#Preview("Leave this care team? (450:3886)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        LeaveTeamSheet(model: LeaveTeamModel(kind: .leave, teamID: TeamFixtures.riverside.teamID,
                                             myUserID: "user-trevor", service: TeamFixtures.service())) { _ in }
    }
}

#Preview("Close this care team?") {
    Color.clear.sheet(isPresented: .constant(true)) {
        LeaveTeamSheet(model: LeaveTeamModel(kind: .close, teamID: TeamFixtures.riverside.teamID,
                                             myUserID: "user-trevor", service: TeamFixtures.service())) { _ in }
    }
}
#endif
