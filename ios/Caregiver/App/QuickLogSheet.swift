import SwiftUI
import CaregiverAPI

/// Interim ⊕ FAB target (ios/specs/views/shell.md decision 3): pick one of the
/// active receiver's trackers, then the existing dynamic log form. The whole
/// sheet is replaced by the Aurora quick-log wizard (ios/specs/views/logging.md).
struct QuickLogSheet: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    private enum LoadState: Equatable {
        case loading
        case loaded([Components.Schemas.Tracker])
        case error(String)
    }

    @State private var state: LoadState = .loading
    @State private var logTracker: Components.Schemas.Tracker?

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    StrideLoadingView()
                case .error(let message):
                    StrideErrorState(message: message) { Task { await load() } }
                case .loaded(let trackers) where trackers.isEmpty:
                    StrideEmptyState(message: "No trackers to log against yet.")
                case .loaded(let trackers):
                    List(trackers, id: \.trackerId) { tracker in
                        Button(tracker.name) { logTracker = tracker }
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .strideBackground()
            .navigationTitle("Log an event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(item: $logTracker) { tracker in
            LogEventView(tracker: tracker, existing: nil) {
                onSaved()
                dismiss()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let receiverID = context.activeReceiver?.receiverId else {
            state = .loaded([])
            return
        }
        state = .loading
        do {
            let trackers = try await session.api
                .listTrackers(path: .init(receiverId: receiverID))
                .ok.body.json.filter { !$0.archived }
            state = .loaded(trackers)
        } catch {
            state = .error(AppError.from(error).message)
        }
    }
}
