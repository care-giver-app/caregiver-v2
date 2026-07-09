import SwiftUI
import CaregiverAPI

/// SwiftUI `Color` for an Aurora tracker hue (the pure `TrackerHue` stays view-free
/// so it can be unit-tested off the main actor).
extension TrackerHue {
    var color: Color {
        switch self {
        case .cyan: Theme.Colors.trackerCyan
        case .teal: Theme.Colors.trackerTeal
        case .violet: Theme.Colors.trackerViolet
        case .infoBlue: Theme.Colors.informational
        }
    }
}

/// Identifiable receiver-id box so entry points present the wizard via
/// `fullScreenCover(item:)`. A Bool cover could open with no active receiver and
/// strand the user on a blank, non-swipe-dismissible screen; keying on the receiver
/// guarantees there's always one (and a close control).
struct AddTrackerTarget: Identifiable { let id: String }

/// The add-tracker wizard (ios/specs/views/add-tracker.md): a full-screen, 2-step
/// (choose template → configure) flow with a back control + 2-dot indicator, no tab
/// bar — presented as a `fullScreenCover` from the Trackers "New" button (admin-only).
struct AddTrackerWizard: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let receiverId: String
    let onCreated: () -> Void

    @State private var model = AddTrackerModel()
    @State private var showCustomNote = false

    private var currentStep: Int { model.phase == .configure ? 1 : 0 }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            topBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .strideBackground()
        .task { await model.load(using: session) }
        .alert("Custom trackers", isPresented: $showCustomNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Building a tracker from scratch is coming soon. For now, start from a template.")
        }
    }

    private var topBar: some View {
        HStack {
            leadingControl
            Spacer()
            StrideStepDots(count: 2, current: currentStep)
            Spacer()
            // Balance the leading control so the dots stay centered.
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
    }

    @ViewBuilder private var leadingControl: some View {
        Button {
            if model.phase == .configure { model.backToChoose() } else { dismiss() }
        } label: {
            Image(systemName: model.phase == .configure ? "chevron.left" : "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            StrideLoadingView().frame(maxHeight: .infinity)
        case .loadError(let message):
            StrideErrorState(message: message) { Task { await model.load(using: session) } }
                .frame(maxHeight: .infinity)
        case .choose:
            AddTrackerChooseStep(
                templates: model.templates,
                onPick: { model.choose($0) },
                onCustom: { showCustomNote = true }
            )
        case .configure:
            AddTrackerConfigureStep(model: model) {
                Task {
                    await model.submit(receiverId: receiverId, using: session) {
                        onCreated()
                        dismiss()
                    }
                }
            }
        }
    }
}
