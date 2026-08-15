import SwiftUI

struct StrideDatePicker: View {
    let label: String
    @Binding var selection: Date
    var displayedComponents: DatePicker.Components = [.date, .hourAndMinute]

    var body: some View {
        DatePicker(label, selection: $selection, displayedComponents: displayedComponents)
            .datePickerStyle(.compact)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        StrideDatePicker(label: "When", selection: .constant(Date()))
    }
    .padding(Theme.Spacing.lg)
    .strideBackground()
}
