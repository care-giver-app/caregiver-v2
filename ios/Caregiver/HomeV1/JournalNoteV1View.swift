import SwiftUI

/// Journal note — one note: its words, the time it is about, who wrote it, and who
/// changed it last if anyone has (PRD "Journal note"; Figma 447:4245).
///
/// Edit in the nav raises Edit journal note, and Delete at the bottom raises Delete this
/// note? (Figma 447:4245). Saving shows the note as it now stands; deleting goes back to
/// Home. Every write is told to Home.
struct JournalNoteV1View: View {
    private enum Sheet: Identifiable {
        case edit(JournalNoteInfo)
        case delete(JournalNoteInfo)

        var id: String {
            switch self {
            case .edit(let n): "edit-\(n.id)"
            case .delete(let n): "delete-\(n.id)"
            }
        }
    }

    let noteID: String
    let receiver: TeamReceiver
    let home: HomeService

    @State private var model: HomeReadModel<JournalNoteInfo>?
    @State private var sheet: Sheet?
    @State private var goHome = false
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
            if let note = model?.value {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { sheet = .edit(note) }
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
            case .edit(let note):
                EditJournalNoteSheet(model: EditJournalNoteModel(note, zone: receiver.timeZone, home: home),
                                     onSaved: { saved in
                                         model?.replace(with: saved)
                                         homeWrote(HomeWrite(receiverID: receiver.id))
                                     },
                                     onFailed: { _ in Task { await model?.load() } })
            case .delete(let note):
                DeleteJournalNoteSheet(model: DeleteJournalNoteModel(note, home: home)) {
                    homeWrote(HomeWrite(receiverID: receiver.id))
                    goHome = true
                }
            }
        }
        .task {
            if let model {
                await model.load()
            } else {
                let model = HomeReadModel.note(noteID, home: home)
                self.model = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: HomeReadModel<JournalNoteInfo>) -> some View {
        switch model.phase {
        case .loading:
            StrideLoadingView()
        case .gone:
            StrideEmptyState(message: HomeText.noteGone)
        case .failed:
            StrideErrorState(message: "Couldn't load this note.") { Task { await model.retry() } }
        case .loaded(let note):
            loaded(JournalNoteContent(note, now: model.now, zone: receiver.timeZone), model: model)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StrideButton(title: "Delete", style: .destructive) { sheet = .delete(note) }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                }
        }
    }

    private func loaded(_ c: JournalNoteContent, model: HomeReadModel<JournalNoteInfo>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.refreshFailed {
                    StrideAlertBanner(message: "Couldn't refresh this note.")
                        .padding(.bottom, Theme.Spacing.md)
                }
                HomeDetailIdentity(title: "Journal note", when: c.when, tile: Theme.Colors.violetTint) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.Colors.trackerViolet)
                }
                HomeDetailNote(text: c.body, size: 16)
                    .padding(.top, 24)
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
}

#if DEBUG
#Preview("Journal note (447:4245)") {
    NavigationStack {
        JournalNoteV1View(noteID: HomeFixtures.afternoonNote.id, receiver: HomeFixtures.eleanor,
                          home: HomeFixtures.service())
    }
}

#Preview("Deleted elsewhere") {
    NavigationStack {
        JournalNoteV1View(noteID: "deleted", receiver: HomeFixtures.eleanor, home: HomeFixtures.service())
    }
}

#Preview("Failed") {
    NavigationStack {
        JournalNoteV1View(noteID: HomeFixtures.afternoonNote.id, receiver: HomeFixtures.eleanor,
                          home: HomeFixtures.service(fail: true))
    }
}
#endif
