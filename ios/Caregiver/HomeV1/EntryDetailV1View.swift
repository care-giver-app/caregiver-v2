import SwiftUI

/// Entry detail — the one screen any entry is read on, whatever state it is in (PRD
/// "Entry detail"; Figma 445:4161 scheduled, 445:4210 unrecorded, 445:4263 logged out of
/// range, 445:4326 skipped). Its tracker, state and time; any value outside its range,
/// named with the range it was expected to hold to; its fields and note; the schedule it
/// came from; who logged or skipped it, and who changed it last.
///
/// What it offers goes by state (`EntryDetailContent.offers`): a scheduled or unrecorded
/// entry offers Log it and Skip at the bottom (Figma 445:4258), each opening Quick log on
/// this one entry with the choice made; it reads itself again when a run saves. A logged
/// or skipped entry offers Edit in the nav and Delete at the bottom (Figma 445:4263,
/// 445:4326), each raising its sheet over this screen. Saving an edit shows the entry as
/// it now stands; deleting one that fulfilled a plan stays here showing it waiting again,
/// while deleting one logged ad hoc goes back to Home. Every write is told to Home.
struct EntryDetailV1View: View {
    /// Edit entry or Delete this entry?, on the entry as it was when raised.
    private enum Sheet: Identifiable {
        case edit(EntryDetailInfo)
        case delete(EntryDetailInfo)

        var id: String {
            switch self {
            case .edit(let d): "edit-\(d.entry.id)"
            case .delete(let d): "delete-\(d.entry.id)"
            }
        }
    }

    let entryID: String
    let receiver: TeamReceiver
    let home: HomeService

    @State private var model: HomeReadModel<EntryDetailInfo>?
    @State private var sheet: Sheet?
    /// Set once the entry is gone for good; Home is gone back to as the sheet goes.
    @State private var goHome = false
    @Environment(\.v1QuickLog) private var quickLog
    @Environment(\.v1QuickLogRuns) private var quickLogRuns
    @Environment(\.v1HomeWrote) private var homeWrote
    @Environment(\.v1PopToHome) private var popToHome

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .homePushedChrome()
        .toolbar {
            if let detail = model?.value, EntryOffer.offers(for: detail.entry.state).contains(.edit) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { sheet = .edit(detail) }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            guard goHome else { return }
            goHome = false
            popToHome()
        }) { sheet in
            switch sheet {
            case .edit(let detail):
                EditEntrySheet(model: EditEntryModel(detail, zone: receiver.timeZone, home: home),
                               onSaved: saved, onFailed: { _ in reload() })
            case .delete(let detail):
                DeleteEntrySheet(model: DeleteEntryModel(detail, home: home),
                                 onDeleted: deleted, onFailed: { _ in reload() })
            }
        }
        // Back from Quick log, which may have logged or skipped this entry.
        .onChange(of: quickLogRuns) { Task { await model?.load() } }
        .task {
            // Every appearance reads it again: it may have been logged, edited or deleted since.
            if let model {
                await model.load()
            } else {
                let model = HomeReadModel.entry(entryID, home: home)
                self.model = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: HomeReadModel<EntryDetailInfo>) -> some View {
        switch model.phase {
        case .loading:
            StrideLoadingView()
        case .gone:
            StrideEmptyState(message: HomeText.entryGone)
        case .failed:
            StrideErrorState(message: "Couldn't load this entry.") { Task { await model.retry() } }
        case .loaded(let detail):
            let content = EntryDetailContent(detail, now: model.now, zone: receiver.timeZone)
            loaded(content, model: model)
                .safeAreaInset(edge: .bottom, spacing: 0) { actions(content.offers, detail: detail) }
        }
    }

    private func loaded(_ c: EntryDetailContent, model: HomeReadModel<EntryDetailInfo>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.refreshFailed {
                    StrideAlertBanner(message: "Couldn't refresh this entry.")
                        .padding(.bottom, Theme.Spacing.md)
                }
                HomeDetailIdentity(title: c.tracker.name, when: c.when, state: c.state,
                                   tile: Color(hex: c.tracker.color)) {
                    Image(systemName: c.tracker.icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.white)
                }

                if let callout = c.callout {
                    self.callout(callout)
                        .padding(.top, 20)
                }

                if let title = c.fieldsTitle {
                    HomeDetailSectionLabel(title: title)
                        .padding(.top, 24)
                        .padding(.bottom, Theme.Spacing.sm)
                    HomeDetailRows(rows: c.fields)
                }

                if let note = c.note {
                    HomeDetailSectionLabel(title: "NOTE")
                        .padding(.top, 20)
                        .padding(.bottom, Theme.Spacing.sm)
                    HomeDetailNote(text: note, size: 15)
                }

                if !c.details.isEmpty {
                    HomeDetailRows(rows: c.details)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .refreshable { await model.load() }
    }

    private func reload() {
        Task { await model?.load() }
    }

    /// Edit entry saved: shown as it now stands, and Home told — with the day it moved to,
    /// so the timeline behind this screen follows it there.
    private func saved(_ saved: EditEntryModel.Saved) {
        model?.replace(with: saved.detail)
        homeWrote(HomeWrite(receiverID: receiver.id, movedTo: saved.movedTo))
    }

    /// Delete this entry? landed: waiting again stays here, gone goes back to Home.
    private func deleted(_ outcome: DeleteEntryModel.Outcome) {
        homeWrote(HomeWrite(receiverID: receiver.id))
        switch outcome {
        case .waitingAgain(let detail): model?.replace(with: detail)
        case .gone: goHome = true
        }
    }

    /// Figma 445:4258: Log it, then Skip, both into Quick log at this entry's step.
    /// Figma 445:4263: Delete, for a logged or skipped entry.
    @ViewBuilder
    private func actions(_ offers: [EntryOffer], detail: EntryDetailInfo) -> some View {
        if offers.contains(.delete) {
            StrideButton(title: "Delete", style: .destructive) { sheet = .delete(detail) }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
        } else if offers.contains(.logIt) || offers.contains(.skip) {
            VStack(spacing: 10) {
                if offers.contains(.logIt) {
                    StrideButton(title: "Log it") { quickLog(.entry(detail, choice: .logIt), receiver: receiver) }
                }
                if offers.contains(.skip) {
                    StrideButton(title: "Skip", style: .secondary) {
                        quickLog(.entry(detail, choice: .skip), receiver: receiver)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    /// Figma 445:4287 (out of range, red) / 445:4235 (unrecorded, amber).
    private func callout(_ callout: EntryDetailContent.Callout) -> some View {
        let (title, lines, color, tint): (String, [String], Color, Color) = switch callout {
        case .outOfRange(let sentences):
            (HomeText.outOfRangeTitle, sentences, Theme.Colors.alert, Theme.Colors.alertTint)
        case .unrecorded:
            (HomeText.unrecordedCalloutTitle, [HomeText.unrecordedCalloutLine],
             Theme.Colors.warning, Theme.Colors.warningTint)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background { RoundedRectangle(cornerRadius: 14).fill(tint) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces shared with Journal note

extension View {
    /// The pushed Home screens' nav: ‹ Back, no title, the Stride background.
    func homePushedChrome() -> some View {
        self
            .strideBackground()
            .toolbar(.visible, for: .navigationBar)
            .strideBackButton()
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.Colors.accent)
    }
}

/// Figma 445:4174: a 56pt tile, the title, and under it the state's badge (entries only)
/// and the time.
struct HomeDetailIdentity<Icon: View>: View {
    let title: String
    let when: String
    var state: EntryState? = nil
    let tile: Color
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16)
                .fill(tile)
                .frame(width: 56, height: 56)
                .overlay { icon }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    if let state { HomeStateBadge(state: state) }
                    Text(when)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Figma 445:4182 / 445:4231 / 445:4283 / 445:4348.
struct HomeStateBadge: View {
    let state: EntryState

    var body: some View {
        let (fg, bg): (Color, Color) = switch state {
        case .scheduled: (Theme.Colors.accent, Theme.Colors.accentTint)
        case .unrecorded: (Theme.Colors.alert, Theme.Colors.alertTint)
        case .logged: (Theme.Colors.success, Theme.Colors.successTint)
        case .skipped: (Theme.Colors.textSecondary, Theme.Colors.accentTint)
        }
        Text(TrackerText.stateLabel(state))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background { RoundedRectangle(cornerRadius: 6).fill(bg) }
    }
}

/// "FIELDS", "PRE-FILLED", "NOTE".
struct HomeDetailSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.72)
            .foregroundStyle(Theme.Colors.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Figma 445:4189: label-and-value rows in one card, hairlines between.
struct HomeDetailRows: View {
    let rows: [DetailRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 {
                    Rectangle().fill(Theme.Colors.border).frame(height: 1)
                }
                HStack(alignment: .center, spacing: 12) {
                    Text(row.label)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: 1)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.value)
                            .font(.system(size: 15, weight: row.expected == nil ? .medium : .semibold))
                            .foregroundStyle(row.expected != nil ? Theme.Colors.alert
                                             : row.pending ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                        if let expected = row.expected {
                            Text(expected)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.alert)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .homeDetailCard()
    }
}

/// Figma 445:4310 / 447:4267: the note's words in a card.
struct HomeDetailNote: View {
    let text: String
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .lineSpacing(size >= 16 ? 4 : 0)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .homeDetailCard()
    }
}

extension View {
    /// The white, hairline-bordered card Home's detail screens sit their rows in.
    func homeDetailCard() -> some View {
        self
            .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
    }
}

#if DEBUG
private enum EntryDetailPreview {
    @MainActor
    static func view(_ id: String, home: HomeService = HomeFixtures.service()) -> some View {
        NavigationStack {
            EntryDetailV1View(entryID: id, receiver: HomeFixtures.eleanor, home: home)
        }
    }
}

#Preview("Scheduled (445:4161)") {
    EntryDetailPreview.view(HomeFixtures.scheduledDetail.entry.id)
}

#Preview("Unrecorded (445:4210)") {
    EntryDetailPreview.view(HomeFixtures.unrecordedDetail.entry.id)
}

#Preview("Logged, out of range (445:4263)") {
    EntryDetailPreview.view(HomeFixtures.loggedOutOfRangeDetail.entry.id)
}

#Preview("Logged from a schedule") {
    EntryDetailPreview.view(HomeFixtures.loggedFromScheduleDetail.entry.id)
}

#Preview("Skipped (445:4326)") {
    EntryDetailPreview.view(HomeFixtures.skippedDetail.entry.id)
}

#Preview("Deleted elsewhere") {
    EntryDetailPreview.view("deleted")
}

#Preview("Failed") {
    EntryDetailPreview.view(HomeFixtures.skippedDetail.entry.id, home: HomeFixtures.service(fail: true))
}
#endif
