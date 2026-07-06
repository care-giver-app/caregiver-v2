import SwiftUI
import CaregiverAPI

/// Detail step of the quick-log wizard (Figma 80:2 enum / 81:2 number): fills in
/// one selected tracker's value fields + an optional note before moving on.
struct QuickLogDetailStep: View {
    @Bindable var model: QuickLogWizardModel
    let index: Int
    let onNext: () -> Void
    let onBack: () -> Void

    private enum Metrics {
        static let navButton: CGFloat = 32
        static let boxRadius: CGFloat = 14
    }

    private var detail: QuickLogDetail { model.details[index] }

    private var hue: Color {
        detail.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent
    }

    private var caption: String {
        "Step \(index + 1) of \(model.details.count) · logging at " +
        model.occurredAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            topRow
            header
            Text(caption)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach($model.details[index].inputs) { $input in
                        fieldRow($input)
                    }
                    noteBox
                }
            }
            StrideButton(
                title: QuickLogWizardModel.primaryTitle(
                    selectedCount: model.selected.count,
                    remainingDetailSteps: model.details.count - index - 1),
                isLoading: model.isBusy
            ) { onNext() }
        }
    }

    // MARK: top row (back · dots · balancer)

    private var topRow: some View {
        HStack {
            navButton(action: onBack)
            Spacer()
            StrideStepDots(count: model.details.count + 1, current: index + 1)
            Spacer()
            navButton(action: nil) // invisible spacer, matches the back button's footprint
        }
    }

    private func navButton(action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: Metrics.navButton, height: Metrics.navButton)
                .background {
                    Circle().fill(Theme.Colors.surface)
                }
        }
        .buttonStyle(.plain)
        .opacity(action == nil ? 0 : 1)
        .disabled(action == nil)
    }

    // MARK: title row

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(hue).frame(width: 11, height: 11)
            Text(detail.tracker.name)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    // MARK: field inputs (spec decision 8)

    @ViewBuilder
    private func fieldRow(_ input: Binding<FieldInput>) -> some View {
        let error = model.fieldErrors[input.wrappedValue.key]
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            switch input.wrappedValue.kind {
            case .enumeration:
                Text(input.wrappedValue.label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                scaleTiles(input)
            case .number:
                surfaceBox {
                    HStack {
                        TextField(input.wrappedValue.label, text: input.textValue)
                            .keyboardType(.decimalPad)
                        if let unit = input.wrappedValue.unit {
                            Text(unit).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            case .text:
                surfaceBox {
                    TextField(input.wrappedValue.label, text: input.textValue)
                }
            case .boolean:
                Toggle(input.wrappedValue.label, isOn: input.boolValue)
                    .toggleStyle(.stride)
                    .foregroundStyle(Theme.Colors.textPrimary)
            case .datetime:
                DatePicker(input.wrappedValue.label, selection: input.dateValue,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tint(Theme.Colors.accent)
            }
            if let error {
                Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.alert)
            }
        }
    }

    /// Equal-width scale tiles for `.enumeration` fields — one tap selects, mirrors
    /// `StrideSelectTile`'s selected treatment (accent fill + accent border).
    private func scaleTiles(_ input: Binding<FieldInput>) -> some View {
        HStack(spacing: 10) {
            ForEach(input.wrappedValue.options, id: \.self) { option in
                let isSelected = input.wrappedValue.textValue == option
                Button {
                    input.wrappedValue.textValue = option
                } label: {
                    Text(option)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.Colors.textOnAccent : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                                .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                                .stroke(isSelected ? Theme.Colors.accent : Theme.Colors.border,
                                        lineWidth: isSelected ? 1.5 : 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noteBox: some View {
        surfaceBox {
            TextField("Add a note (optional)", text: $model.details[index].note, axis: .vertical)
        }
    }

    @ViewBuilder
    private func surfaceBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: Metrics.boxRadius)
                    .fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.boxRadius)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            }
    }
}

#Preview("Detail step — enum") {
    let tracker = Components.Schemas.Tracker(
        trackerId: "t-mood", receiverId: "r1", careGroupId: "g1",
        name: "Mood", kind: .event, color: "7c6ff0",
        fields: [.init(key: "mood", label: "Mood", _type: ._enum, options: ["Low", "OK", "Good"])],
        createdBy: "u1", createdAt: Date(), archived: false)
    let model = QuickLogWizardModel()
    model.selected = [tracker.trackerId]
    model.details = [QuickLogDetail(tracker: tracker, inputs: DynamicFormBuilder.inputs(for: tracker.fields))]
    return QuickLogDetailStep(model: model, index: 0, onNext: {}, onBack: {})
        .padding(Theme.Spacing.lg)
        .strideBackground()
}

#Preview("Detail step — number") {
    let tracker = Components.Schemas.Tracker(
        trackerId: "t-pain", receiverId: "r1", careGroupId: "g1",
        name: "Pain level", kind: .measurement, color: "93C5FD",
        fields: [.init(key: "pain", label: "Pain", _type: .number, unit: "mmHg")],
        createdBy: "u1", createdAt: Date(), archived: false)
    let model = QuickLogWizardModel()
    model.selected = [tracker.trackerId]
    model.details = [QuickLogDetail(tracker: tracker, inputs: DynamicFormBuilder.inputs(for: tracker.fields))]
    return QuickLogDetailStep(model: model, index: 0, onNext: {}, onBack: {})
        .padding(Theme.Spacing.lg)
        .strideBackground()
}
