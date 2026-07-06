import SwiftUI
import CaregiverAPI

/// Step 0 of the quick-log wizard (Figma 75:2): multi-select the receiver's
/// trackers, adjust the shared occurred-at, continue.
struct QuickLogSelectStep: View {
    @Bindable var model: QuickLogWizardModel
    let receiverName: String
    let onNext: () -> Void

    @State private var showTimePicker = false

    private var needingCount: Int {
        QuickLogWizardModel.needingDetails(model.trackers, selected: model.selected).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            StrideStepDots(count: needingCount + 1, current: 0)
                .frame(maxWidth: .infinity, alignment: .center)
            header
            Text("Tap a tracker to log it now")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(model.trackers) { tracker in
                        StrideSelectTile(
                            name: tracker.name,
                            hue: tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent,
                            isSelected: model.selected.contains(tracker.trackerId)
                        ) {
                            if model.selected.contains(tracker.trackerId) {
                                model.selected.remove(tracker.trackerId)
                            } else {
                                model.selected.insert(tracker.trackerId)
                            }
                        }
                    }
                }
            }
            if let helper = QuickLogWizardModel.helperText(
                selectedCount: model.selected.count, needingDetails: needingCount) {
                Text(helper)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            StrideButton(
                title: QuickLogWizardModel.primaryTitle(
                    selectedCount: model.selected.count, remainingDetailSteps: needingCount),
                isLoading: model.isBusy
            ) { onNext() }
                .disabled(model.selected.isEmpty || model.isBusy)
                .opacity(model.selected.isEmpty ? 0.5 : 1)
        }
        .sheet(isPresented: $showTimePicker) { timePickerSheet }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Log events").font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("for \(receiverName)").font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { showTimePicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(timeLabel)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Theme.Colors.surface))
            }
            .buttonStyle(.plain)
        }
    }

    private var timeLabel: String {
        abs(model.occurredAt.timeIntervalSinceNow) < 60
            ? "Now"
            : model.occurredAt.formatted(date: .omitted, time: .shortened)
    }

    private var timePickerSheet: some View {
        VStack(spacing: Theme.Spacing.md) {
            DatePicker("When", selection: $model.occurredAt, in: ...Date())
                .datePickerStyle(.graphical)
            StrideButton(title: "Done") { showTimePicker = false }
        }
        .padding(Theme.Spacing.lg)
        .strideBackground()
        .presentationDetents([.medium])
    }
}

#Preview("Select step") {
    let model = QuickLogWizardModel()
    model.trackers = [
        .init(trackerId: "t-meals", receiverId: "r1", careGroupId: "g1",
              name: "Meals", kind: .event, color: "4dd6e6", fields: [],
              createdBy: "u1", createdAt: Date(), archived: false),
        .init(trackerId: "t-hydration", receiverId: "r1", careGroupId: "g1",
              name: "Hydration", kind: .event, color: "3db8c4", fields: [],
              createdBy: "u1", createdAt: Date(), archived: false),
        .init(trackerId: "t-mood", receiverId: "r1", careGroupId: "g1",
              name: "Mood", kind: .event, color: "7c6ff0",
              fields: [.init(key: "mood", label: "Mood", _type: ._enum,
                             options: ["Low", "OK", "Good"])],
              createdBy: "u1", createdAt: Date(), archived: false),
        .init(trackerId: "t-pain", receiverId: "r1", careGroupId: "g1",
              name: "Pain level", kind: .measurement, color: "93C5FD",
              fields: [.init(key: "pain", label: "Pain", _type: .number, unit: "/10")],
              createdBy: "u1", createdAt: Date(), archived: false),
    ]
    model.selected = Set(model.trackers.map(\.trackerId))
    return QuickLogSelectStep(model: model, receiverName: "Eleanor") {}
        .padding(Theme.Spacing.lg)
        .strideBackground()
}
