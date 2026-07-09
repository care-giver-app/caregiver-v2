import SwiftUI
import CaregiverAPI

/// Step 2 of the add-tracker wizard (add-tracker.md decisions 4/9/13): pre-filled
/// name + Aurora color swatch + read-only field rows + an editable ALERT min/max row
/// for every `number` field, then Create. Field schema is shown read-only (v1 edits
/// thresholds only).
struct AddTrackerConfigureStep: View {
    @Bindable var model: AddTrackerModel
    let onCreate: () -> Void

    private var fields: [Components.Schemas.Field] { model.selected?.fields ?? [] }
    private var numberFields: [Components.Schemas.Field] { fields.filter { $0._type == .number } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                nameField
                colorPicker
                fieldsCard
                if !numberFields.isEmpty { alertsCard }
                if let error = model.submitError {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.alert)
                }
                StrideButton(title: "Create tracker", isLoading: model.isSubmitting, action: onCreate)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 12)
                .fill(model.selectedHue.color.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: model.selected?.icon ?? "square.dashed")
                        .font(.system(size: 18))
                        .foregroundStyle(model.selectedHue.color)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Configure")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let kind = model.selected?.kind {
                    Text(AddTrackerLogic.kindLabel(kind))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("NAME")
            StrideField(placeholder: "Tracker name", text: $model.name)
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("COLOR")
            HStack(spacing: Theme.Spacing.md) {
                ForEach(TrackerHue.allCases, id: \.self) { hue in
                    Button { model.selectedHue = hue } label: {
                        Circle()
                            .fill(hue.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle().stroke(
                                    Theme.Colors.textPrimary,
                                    lineWidth: model.selectedHue == hue ? 2.5 : 0
                                )
                                .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hue.rawValue)
                    .accessibilityAddTraits(model.selectedHue == hue ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("FIELDS")
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element.key) { index, field in
                    if index > 0 { Divider().overlay(Theme.Colors.border) }
                    HStack {
                        Text(field.label)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text(fieldMeta(field))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
        }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("ALERTS")
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(numberFields, id: \.key) { field in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(field.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        boundField("Min", text: minBinding(field.key))
                        boundField("Max", text: maxBinding(field.key))
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
        }
    }

    private func boundField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: 64, height: 40)
            .background { RoundedRectangle(cornerRadius: 10).fill(Theme.Colors.surfaceHi) }
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.border, lineWidth: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func fieldMeta(_ field: Components.Schemas.Field) -> String {
        var parts = [field._type.rawValue]
        if let unit = field.unit, !unit.isEmpty { parts.append(unit) }
        return parts.joined(separator: " · ")
    }

    // Bindings into the per-field threshold dict (seeded for every number field).
    private func minBinding(_ key: String) -> Binding<String> {
        Binding(get: { model.thresholds[key]?.min ?? "" },
                set: { model.thresholds[key]?.min = $0 })
    }

    private func maxBinding(_ key: String) -> Binding<String> {
        Binding(get: { model.thresholds[key]?.max ?? "" },
                set: { model.thresholds[key]?.max = $0 })
    }
}
