import SwiftUI

/// Jump to day — which day Home's timeline shows (PRD "Jump to day"; Figma 447:4140). A
/// month calendar in the receiver's zone that stops at today; picking a day selects it
/// and stays, Done returns to Home showing the day picked.
struct JumpToDaySheet: View {
    let onDone: (LocalDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: JumpToDayModel
    @State private var height: CGFloat = 460

    init(today: LocalDay, showing: LocalDay, onDone: @escaping (LocalDay) -> Void) {
        self.onDone = onDone
        _model = State(initialValue: JumpToDayModel(today: today, showing: showing))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, Theme.Spacing.md)
            monthBar
                .padding(.bottom, 14)
            weekdays
                .padding(.bottom, 6)
            grid
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 28)
        .padding(.bottom, Theme.Spacing.md)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.surface)
        .presentationCornerRadius(22)
    }

    /// Jump to day · Done. Dragging the sheet down leaves the day as it was.
    private var header: some View {
        ZStack {
            Text("Jump to day")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button("Done") {
                    onDone(model.selected)
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(.plain)
            }
        }
        .frame(height: 26)
    }

    private var monthBar: some View {
        HStack {
            Text(ChooseDatesSheet.monthTitle(model.month))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 20) {
                Button { model.goBack() } label: { chevron("chevron.left", enabled: true) }
                    .accessibilityLabel("Previous month")
                Button { model.goForward() } label: { chevron("chevron.right", enabled: model.canGoForward) }
                    .disabled(!model.canGoForward)
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)
        }
    }

    private func chevron(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(enabled ? Theme.Colors.accent : Theme.Colors.border)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle().inset(by: -10))
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            Button { model.pick(day) } label: {
                                StrideCalendarDay(day: day.day, state: model.state(of: day))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isDisabled(day))
                            .accessibilityLabel(HomeText.dayTitle(day, today: model.today).detail)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 44)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Jump to day (Figma 447:4140)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        JumpToDaySheet(today: LocalDay(year: 2026, month: 10, day: 25),
                       showing: LocalDay(year: 2026, month: 10, day: 23), onDone: { _ in })
    }
}
#endif
