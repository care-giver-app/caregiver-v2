import SwiftUI

/// Journal note — one note: its words, the time it is about, who wrote it, and who
/// changed it last if anyone has (PRD "Journal note"; Figma 447:4245).
///
/// Reads only for now. Edit (Edit journal note, in the nav) and Delete (Delete this
/// note?, at the bottom) arrive with Home's write side.
struct JournalNoteV1View: View {
    let noteID: String
    let receiver: TeamReceiver
    let home: HomeService

    @State private var model: HomeReadModel<JournalNoteInfo>?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .homePushedChrome()
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
