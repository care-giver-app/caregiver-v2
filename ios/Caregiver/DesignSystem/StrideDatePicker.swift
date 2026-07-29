import SwiftUI

/// Aurora-styled wrapper around the compact `DatePicker`. The compact style's
/// date/time pill is UIKit-rendered chrome that `.tint`/`.foregroundStyle` alone
/// don't reliably restyle — and since the app force-locks `UIUserInterfaceStyle:
/// Light` (Info.plist) while Aurora surfaces are dark, the digits render washed
/// out. `.colorScheme(.dark)` forces that chrome into its dark variant so the
/// numbers stay legible against our surfaces.
struct StrideDatePicker: View {
    let label: String
    @Binding var selection: Date
    var displayedComponents: DatePicker.Components = [.date, .hourAndMinute]

    var body: some View {
        DatePicker(label, selection: $selection, displayedComponents: displayedComponents)
            .datePickerStyle(.compact)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent)
            .colorScheme(.dark)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        StrideDatePicker(label: "When", selection: .constant(Date()))
    }
    .padding(Theme.Spacing.lg)
    .strideBackground()
}
