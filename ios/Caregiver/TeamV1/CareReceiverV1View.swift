import SwiftUI

/// Tells the app a care receiver changed in a way other screens show — renamed, moved to
/// another time zone, archived or restored — so Home and Team read their receivers again.
/// V1TabShell supplies it; elsewhere it does nothing.
struct V1ReceiverChanged: Sendable {
    let changed: @MainActor @Sendable () -> Void

    @MainActor func callAsFunction() { changed() }
}

private struct V1ReceiverChangedKey: EnvironmentKey {
    static let defaultValue = V1ReceiverChanged {}
}

extension EnvironmentValues {
    var v1ReceiverChanged: V1ReceiverChanged {
        get { self[V1ReceiverChangedKey.self] }
        set { self[V1ReceiverChangedKey.self] = newValue }
    }
}

/// Care receiver (PRD "Care receiver"; Figma 451:3428, 451:3553 just added): one screen for
/// the instructions, who to call, and who is meant to be there. Pushed from Team's chevron,
/// Care team's archived receivers, and Home's header. Admins change it through sheets;
/// archived, it is all unchanged but read-only, with Restore for an admin.
struct CareReceiverV1View: View {
    let service: TeamService

    @State private var model: CareReceiverModel
    @State private var sheet: CareReceiverSheet?
    @Environment(\.openURL) private var openURL
    @Environment(\.v1ReceiverChanged) private var receiverChanged

    init(receiver: TeamReceiver, service: TeamService, model: CareReceiverModel? = nil) {
        self.service = service
        _model = State(initialValue: model ?? CareReceiverModel(receiver: receiver, service: service))
    }

    var body: some View {
        Group {
            switch model.detail {
            case .loading:
                StrideLoadingView()
            case .failed:
                StrideErrorState(message: TeamText.careReceiverFailed) { Task { await model.retry() } }
            case .loaded(let info):
                content(info)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.visible, for: .navigationBar)
        .strideBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canWrite, let info = model.detail.value {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(TeamText.edit) { sheet = .editReceiver(info) }
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
    }

    // MARK: - The screen

    private func content(_ info: CareReceiverInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identity(info)
                if info.isArchived {
                    archivedCallout(info).padding(.top, 16)
                }
                // Each part is several views; one stack each, so the gap above is the part's.
                section { instructions(info) }.padding(.top, 22)
                section { contacts(info) }.padding(.top, 22)
                section { coverage }.padding(.top, 22)
                if model.isAdmin {
                    archiveOrRestore(info).padding(.top, 22)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    private func identity(_ info: CareReceiverInfo) -> some View {
        HStack(spacing: 14) {
            TeamMonogram(name: info.name, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(TeamText.identityLine(zone: info.timeZone, team: info.teamName))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .lineLimit(2)
        }
    }

    /// Not in Figma: who archived them and that it is all read-only now.
    private func archivedCallout(_ info: CareReceiverInfo) -> some View {
        Text(TeamText.archivedLine(by: info.archivedByName, at: info.archivedAt, now: model.now, zone: info.timeZone))
            .font(.system(size: 14))
            .foregroundStyle(Theme.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.warningTint) }
    }

    // MARK: Care instructions

    @ViewBuilder
    private func instructions(_ info: CareReceiverInfo) -> some View {
        if let written = info.instructions, !written.body.isEmpty {
            label(TeamText.careInstructions, action: model.canWrite ? TeamText.edit : nil) {
                sheet = .instructions(info)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(written.body)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(TeamText.changedBy(written.updatedByName, at: written.updatedAt, now: model.now,
                                        zone: info.timeZone))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .teamCard()
        } else {
            label(TeamText.careInstructions)
            empty(TeamText.noInstructions)
            if model.canWrite {
                addRow(TeamText.writeInstructions) { sheet = .instructions(info) }
            }
        }
    }

    // MARK: Emergency contacts

    @ViewBuilder
    private func contacts(_ info: CareReceiverInfo) -> some View {
        if info.contacts.isEmpty {
            label(TeamText.emergencyContacts)
            empty(TeamText.noContacts)
            if model.canWrite {
                addRow(TeamText.addContact) { sheet = .contacts(info) }
            }
        } else {
            label(TeamText.emergencyContacts, action: model.canWrite ? TeamText.edit : nil) {
                sheet = .contacts(info)
            }
            VStack(spacing: 0) {
                ForEach(Array(info.contacts.enumerated()), id: \.element.id) { i, contact in
                    if i > 0 { TeamRowDivider(inset: 60) }
                    contactRow(contact)
                }
            }
            .teamCard()
        }
    }

    /// A row that dials, not a paragraph to read a number out of (PRD).
    private func contactRow(_ contact: EmergencyContactInfo) -> some View {
        HStack(spacing: 12) {
            TeamMonogram(name: contact.name)
            TeamRowText(title: contact.name, detail: TeamText.contactLine(contact))
            if let url = Self.dial(contact.phone) {
                Button { openURL(url) } label: {
                    Text(TeamText.call)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background { RoundedRectangle(cornerRadius: 10).fill(Theme.Colors.accentTint) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(contact.name)")
            }
        }
        .teamRow()
    }

    /// `tel:` with the number's digits and a leading +; nil when it has no digits to dial.
    static func dial(_ phone: String) -> URL? {
        var digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") { digits = "+" + digits }
        return URL(string: "tel:\(digits)")
    }

    // MARK: Who is meant to be there

    @ViewBuilder
    private var coverage: some View {
        label(TeamText.whoIsMeantToBeThere)
        if model.keepsNoRoster {
            // Figma 451:3553: a team that coordinates informally sees that it keeps no roster.
            empty(TeamText.nobodyAssigned)
            if model.canWrite {
                addRow(TeamText.addAssignment) { sheet = .assignment(nil) }
                addRow(TeamText.addCoverage) { sheet = .coverage(nil) }
            }
        } else {
            section { onDuty }
            assignments.padding(.top, 16)
            schedules.padding(.top, 22)
        }
    }

    @ViewBuilder
    private var onDuty: some View {
        switch model.onDuty {
        case .loading:
            ProgressView().tint(Theme.Colors.accent)
        case .failed:
            failure(TeamText.onDutyFailed)
        case .loaded(let now) where now.isEmpty:
            Text(TeamText.nobodyOnDuty)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textTertiary)
        case .loaded(let now):
            // Overlapping assignments are ordinary: a family member and an aide together.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(now) { a in
                    StrideCoverageRow(title: TeamText.onDuty(a.caregiverName),
                                      detail: TeamText.until(a.ends, now: model.localNow))
                }
            }
        }
    }

    @ViewBuilder
    private var assignments: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(TeamText.assignmentsAhead, action: model.canWrite ? TeamText.add : nil) {
                sheet = .assignment(nil)
            }
            switch model.assignments {
            case .loading:
                EmptyView()
            case .failed:
                failure(TeamText.assignmentsFailed)
            case .loaded(let list) where list.isEmpty:
                empty(TeamText.noAssignmentsAhead)
            case .loaded(let list):
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { TeamRowDivider(inset: 60) }
                        rosterRow(enabled: model.canWrite, action: { sheet = .assignment(a) }) {
                            TeamMonogram(name: a.caregiverName)
                            TeamRowText(title: a.caregiverName, detail: TeamText.assignmentLine(a))
                        }
                    }
                }
                .teamCard()
            }
        }
    }

    @ViewBuilder
    private var schedules: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(TeamText.coverageSchedules, action: model.canWrite ? TeamText.add : nil) {
                sheet = .coverage(nil)
            }
            switch model.coverage {
            case .loading:
                EmptyView()
            case .failed:
                failure(TeamText.coverageFailed)
            case .loaded(let list) where list.isEmpty:
                empty(TeamText.noCoverageSchedules)
            case .loaded(let list):
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { TeamRowDivider(inset: 60) }
                        rosterRow(enabled: model.canWrite, action: { sheet = .coverage(c) }) {
                            TeamTile(icon: "calendar")
                            TeamRowText(title: TeamText.coverageTitle(days: c.days, interval: c.interval),
                                        detail: TeamText.coverageLine(c, today: model.today))
                        }
                    }
                }
                .teamCard()
            }
        }
    }

    /// A roster row: opens its sheet, with a chevron, for an admin; read-only for anyone else.
    @ViewBuilder
    private func rosterRow<Content: View>(enabled: Bool, action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        let row = HStack(spacing: 12) {
            content()
            if enabled { TeamChevron() }
        }
        .teamRow()
        if enabled {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    // MARK: Archive and Restore

    @ViewBuilder
    private func archiveOrRestore(_ info: CareReceiverInfo) -> some View {
        if info.isArchived {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { if await model.restore() { receiverChanged() } }
                } label: {
                    HStack {
                        Text(TeamText.restoreReceiver)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                        Spacer()
                        if model.isRestoring { ProgressView().tint(Theme.Colors.accent) }
                    }
                    .teamRow()
                    .teamCard()
                }
                .buttonStyle(.plain)
                .disabled(model.isRestoring)
                if let error = model.restoreError {
                    failure(error)
                }
            }
        } else {
            Button { sheet = .archive(info) } label: {
                Text(TeamText.archiveReceiver)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.alert)
                    .teamRow()
                    .teamCard()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Parts

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
    }

    /// A section's label, with an admin's action at its trailing edge (Figma "Label: …").
    private func label(_ text: String, action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        HStack {
            TeamSectionLabel(text)
            Spacer()
            if let action {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .padding(.bottom, Theme.Spacing.sm)
                .accessibilityLabel("\(action) \(text.lowercased())")
            }
        }
    }

    /// Figma "Empty: …": one muted line on a card.
    private func empty(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 15))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .teamCard()
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { AddTrackerActionRow(title: title) }
            .buttonStyle(.plain)
            .padding(.top, 8)
    }

    private func failure(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 14))
            .foregroundStyle(Theme.Colors.alert)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(_ sheet: CareReceiverSheet) -> some View {
        switch sheet {
        case .editReceiver(let info):
            EditCareReceiverSheet(model: EditCareReceiverModel(info: info, service: service)) { _ in
                receiverChanged()
                Task { await model.load() }
            }
        case .instructions(let info):
            EditInstructionsSheet(model: EditInstructionsModel(info: info, service: service)) { model.adopt($0) }
        case .contacts(let info):
            EmergencyContactsSheet(model: EmergencyContactsModel(info: info, service: service)) { model.adopt($0) }
        case .assignment(let existing):
            AssignmentSheet(model: AssignmentModel(
                receiverID: model.receiver.id, receiverName: model.name, zone: model.zone, existing: existing,
                members: model.members.value ?? [], rule: existing.flatMap(model.rule(for:)), service: service
            ), membersFailed: model.members == .failed) {
                Task { await model.load() }
            }
        case .coverage(let existing):
            CoverageScheduleSheet(model: CoverageScheduleModel(
                receiverID: model.receiver.id, receiverName: model.name, zone: model.zone, existing: existing,
                members: model.members.value ?? [], service: service
            ), membersFailed: model.members == .failed) {
                Task { await model.load() }
            }
        case .archive(let info):
            ArchiveReceiverSheet(model: ArchiveReceiverModel(receiverID: info.id, name: info.name, service: service)) {
                // Back to Care receiver, now archived (PRD); Home chooses again if it was theirs.
                receiverChanged()
                Task { await model.load() }
            }
        }
    }
}

/// The sheets Care receiver raises (PRD: every one of them is a sheet).
enum CareReceiverSheet: Identifiable {
    case editReceiver(CareReceiverInfo)
    case instructions(CareReceiverInfo)
    case contacts(CareReceiverInfo)
    /// Nil adds one.
    case assignment(AssignmentInfo?)
    /// Nil adds one.
    case coverage(CoverageScheduleInfo?)
    case archive(CareReceiverInfo)

    var id: String {
        switch self {
        case .editReceiver: "edit"
        case .instructions: "instructions"
        case .contacts: "contacts"
        case .assignment(let a): "assignment-\(a?.id ?? "new")"
        case .coverage(let c): "coverage-\(c?.id ?? "new")"
        case .archive: "archive"
        }
    }
}

#if DEBUG
private enum CareReceiverPreview {
    @MainActor static func view(_ receiver: TeamReceiver, service: TeamService = TeamFixtures.service())
        -> some View {
        NavigationStack {
            CareReceiverV1View(receiver: receiver, service: service)
        }
    }
}

#Preview("Care receiver (451:3428)") {
    CareReceiverPreview.view(HomeFixtures.eleanor.managed(by: HomeFixtures.riverside))
}

#Preview("Just added (451:3553)") {
    CareReceiverPreview.view(HomeFixtures.harold.managed(by: HomeFixtures.riverside))
}

#Preview("Caregiver's view") {
    CareReceiverPreview.view(HomeFixtures.walter.managed(by: HomeFixtures.johnson))
}

#Preview("Archived") {
    CareReceiverPreview.view(HomeFixtures.rosa.managed(by: HomeFixtures.riverside))
}
#endif
