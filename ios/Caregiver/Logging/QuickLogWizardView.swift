import SwiftUI

/// The quick-log wizard sheet (ios/specs/views/logging.md): select → detail
/// steps → submit, with per-tracker results on partial failure (decision 5).
struct QuickLogWizardView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    @Environment(\.dismiss) private var dismiss
    let onLogged: () -> Void

    @State private var model = QuickLogWizardModel()

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                StrideLoadingView()
            case .loadError(let message):
                StrideErrorState(message: message) { Task { await load() } }
            case .select where model.trackers.isEmpty:
                StrideEmptyState(message: "No trackers to log against yet.")
            case .select:
                QuickLogSelectStep(model: model,
                                   receiverName: context.activeReceiver?.name ?? "") {
                    Task { await advanceAndMaybeDismiss() }
                }
            case .detail(let i):
                QuickLogDetailStep(model: model, index: i,
                                   onNext: { Task { await advanceAndMaybeDismiss() } },
                                   onBack: { model.back() })
            case .results:
                QuickLogResultsStep(model: model,
                                    onRetry: { Task { await retryAndMaybeDismiss() } },
                                    onDone: { finish() })
            }
        }
        .padding(Theme.Spacing.lg)
        .strideBackground()
        .presentationDetents([.fraction(0.75)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isBusy)
        .task { await load() }
    }

    private func load() async {
        guard let id = context.activeReceiver?.receiverId else {
            model.trackers = []; model.phase = .select
            return
        }
        await model.load(receiverID: id, using: session)
    }

    private func advanceAndMaybeDismiss() async {
        await model.advance(using: session)
        if case .results = model.phase, model.allSucceeded { finish() }
    }

    private func retryAndMaybeDismiss() async {
        await model.retryFailed(using: session)
        if model.allSucceeded { finish() }
    }

    private func finish() {
        if model.anySucceeded { onLogged() }
        dismiss()
    }
}
