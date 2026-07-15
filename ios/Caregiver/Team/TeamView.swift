import SwiftUI

/// Interim Team tab (ios/specs/views/shell.md decision 4) — replaced by the
/// designed Team screen (ios/specs/views/team.md) in its own build pass.
struct TeamView: View {
    var body: some View {
        StrideEmptyState(message: "Team view coming soon.")
            .strideBackground()
            .navigationTitle("Team")
    }
}

#Preview {
    NavigationStack { TeamView() }
}
