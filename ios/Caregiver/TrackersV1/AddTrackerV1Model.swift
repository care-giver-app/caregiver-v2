import Foundation

/// Add tracker (PRD "Add tracker"): one sheet in parts. Choose a template or Start from
/// scratch, adjust what it brought, and Create. Nothing is sent until Create.
///
/// Named `AddTrackerV1Model` beside the pre-/v1 `AddTrackerModel` in `Trackers/`.
@MainActor
@Observable
final class AddTrackerV1Model {
    /// The sheet's parts. Each swaps in place; none is a push (PRD exits "as: stays").
    enum Part: Equatable {
        case choose, adjust, iconColor
    }

    enum Templates: Equatable {
        case loading
        case loaded([TrackerTemplate])
        case failed(AppError)
    }

    /// What Start from scratch begins on until the admin picks otherwise: the catalog's
    /// generic clipboard, on the app's cyan.
    static let scratchIcon = "list.clipboard"
    static let scratchColor = "#1c8fe0"

    var part: Part = .choose
    private(set) var templates: Templates = .loading
    /// What the second part edits. Picking a template or Start from scratch replaces it;
    /// Back to the first part keeps it until then.
    var draft: TrackerDraft = .scratch(icon: scratchIcon, color: scratchColor)
    private(set) var isCreating = false
    /// The last Create failed; the sheet stays, with the draft as it was.
    private(set) var createFailed: AppError?

    let receiver: TeamReceiver
    private let service: TrackersService

    init(receiver: TeamReceiver, service: TrackersService) {
        self.receiver = receiver
        self.service = service
    }

    // MARK: First part

    /// In the order the server serves them.
    func loadTemplates() async {
        do {
            templates = .loaded(try await service.listTemplates())
        } catch {
            templates = .failed(AppError.from(error))
        }
    }

    func retryTemplates() async {
        templates = .loading
        await loadTemplates()
    }

    func choose(_ template: TrackerTemplate) {
        draft = TrackerDraft(template)
        createFailed = nil
        part = .adjust
    }

    func startFromScratch() {
        draft = .scratch(icon: Self.scratchIcon, color: Self.scratchColor)
        createFailed = nil
        part = .adjust
    }

    /// Back, on the second part.
    func back() {
        part = .choose
    }

    // MARK: Second part

    /// The red x, or A field's Remove. The tracker doesn't exist yet, so this is a delete.
    func remove(_ id: FieldDraft.ID) {
        draft.fields.removeAll { $0.id == id }
    }


    var problems: [String] { draft.problems }
    var canCreate: Bool { problems.isEmpty && !isCreating }

    /// Sends the tracker. Returns it once made; nil when it can't be sent or failed,
    /// leaving the sheet where it was.
    func create() async -> TrackerProfile? {
        guard canCreate else { return nil }
        isCreating = true
        createFailed = nil
        defer { isCreating = false }
        do {
            return try await service.addTracker(receiver.id, draft.write)
        } catch {
            createFailed = AppError.from(error)
            return nil
        }
    }
}

extension FieldDraft {
    /// "Number · required" (Figma `Stride/Field Row` 405:3234).
    var rowSummary: String {
        required ? "\(kind.chipTitle) · required" : kind.chipTitle
    }
}
