import SwiftUI
import CaregiverAPI

/// Step 1 of the add-tracker wizard (add-tracker.md decision 3): a 2-column gallery
/// of `StrideTemplateCard`s (hue icon + raw `kind` badge) plus the Custom escape
/// hatch. Dumb — selection is handled by the parent wizard.
struct AddTrackerChooseStep: View {
    let templates: [Components.Schemas.TrackerTemplate]
    let onPick: (Components.Schemas.TrackerTemplate) -> Void
    let onCustom: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a tracker")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Start from a template — you can tweak it next.")
                        .font(Theme.Typography.subhead)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm + 4) {
                    ForEach(templates, id: \.templateId) { template in
                        Button { onPick(template) } label: {
                            StrideTemplateCard(style: .template(
                                name: template.name,
                                kind: AddTrackerLogic.kindLabel(template.kind),
                                icon: template.icon ?? "square.dashed",
                                hue: AddTrackerLogic.hue(forTemplateID: template.templateId).color
                            ))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { onCustom() } label: {
                        StrideTemplateCard(style: .custom)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }
}
