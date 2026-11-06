import SwiftUI

/// Create your first care team — pushed from Join a care team
/// (PRD "Getting into the app"; Figma 358:3441).
struct CreateFirstCareTeamView: View {
    let service: GettingInService
    let onCreated: () async -> Void

    @State private var model: CreateFirstCareTeamModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .strideBackground()
        .toolbar(.visible, for: .navigationBar)
        // Back buttons always read "‹ Back"; the iOS 26 system one is a bare chevron.
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Theme.Colors.accent)
        .onAppear {
            if model == nil {
                model = CreateFirstCareTeamModel(service: service, onCreated: onCreated)
            }
        }
    }

    private func content(_ model: CreateFirstCareTeamModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GettingInHeading(title: "Welcome to CareToSher",
                                 subtitle: "Name your care team to get started")
                    .padding(.bottom, 28)

                StrideSectionHeader(title: "Care team name")
                    .padding(.bottom, 10)
                StrideField(placeholder: "Care team name", icon: "person", text: $model.name)
                    .textContentType(.organizationName)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await model.create() } }
                if let error = model.error {
                    StrideAlertBanner(message: error.message)
                        .padding(.top, 10)
                }

                StrideButton(title: "Create team", isLoading: model.isBusy) {
                    Task { await model.create() }
                }
                .padding(.top, 23)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

#if DEBUG
#Preview("Create your first care team") {
    NavigationStack {
        CreateFirstCareTeamView(service: GettingInFixtures.service(), onCreated: {})
    }
}

#Preview("Server refused the name") {
    NavigationStack {
        CreateFirstCareTeamView(
            service: GettingInFixtures.service(createTeam: .rejected("name must be at most 100 characters")),
            onCreated: {}
        )
    }
}
#endif
