import SwiftUI

/// Choose dates — narrows one tracker's entries to a stretch of days in the
/// receiver's zone (PRD "Choose dates"; Figma 514:1079, sheet 514:1117). Done
/// hands back what to narrow to; Cancel changes nothing.
struct ChooseDatesSheet: View {
    let onDone: (EntryWindow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: ChooseDatesModel
    @State private var height: CGFloat = 520

    init(today: LocalDay, seed: (first: LocalDay, last: LocalDay)?, onDone: @escaping (EntryWindow) -> Void) {
        self.onDone = onDone
        _model = State(initialValue: ChooseDatesModel(today: today, seed: seed))
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
                .padding(.bottom, Theme.Spacing.md)
            stretch
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

    /// Cancel · Choose dates · Done.
    private var header: some View {
        ZStack {
            Text("Choose dates")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Button("Done") {
                    onDone(model.outcome)
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.accent)
            .buttonStyle(.plain)
        }
        .frame(height: 26)
    }

    /// "November 2026", back a month always, forward only as far as this one.
    private var monthBar: some View {
        HStack {
            Text(Self.monthTitle(model.month))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 20) {
                Button { model.goBack() } label: {
                    chevron("chevron.left", enabled: model.canGoBack)
                }
                .accessibilityLabel("Previous month")
                Button { model.goForward() } label: {
                    chevron("chevron.right", enabled: model.canGoForward)
                }
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

    /// Figma 514:1144: the month's weeks, Sunday first.
    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            Button { model.tap(day) } label: {
                                StrideCalendarDay(day: day.day, state: model.state(of: day))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isDisabled(day))
                            .accessibilityLabel(Self.dayName(day))
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 44)
                        }
                    }
                }
            }
        }
    }

    /// Figma 514:1276: the stretch written out, and Clear.
    private var stretch: some View {
        HStack {
            Text(model.stretchLabel ?? "All entries")
                .font(.system(size: 15, weight: model.stretchLabel == nil ? .medium : .semibold))
                .foregroundStyle(model.stretchLabel == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
            Spacer()
            if model.stretchLabel != nil {
                Button("Clear") { model.clear() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
    }

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                     "August", "September", "October", "November", "December"]
    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
                                       "Friday", "Saturday"]

    static func monthTitle(_ month: CalendarMonth) -> String {
        "\(monthNames[month.month - 1]) \(month.year)"
    }

    private static func dayName(_ day: LocalDay) -> String {
        "\(weekdayNames[day.weekday - 1]), \(monthNames[day.month - 1]) \(day.day)"
    }
}

#if DEBUG
/// Sunday Nov 8 2026 — today in the Figma frames.
private let previewToday = LocalDay(year: 2026, month: 11, day: 8)

#Preview("Stretch chosen (Figma 514:1117)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ChooseDatesSheet(today: previewToday,
                         seed: (LocalDay(year: 2026, month: 11, day: 2), LocalDay(year: 2026, month: 11, day: 7)),
                         onDone: { _ in })
    }
}

#Preview("Nothing chosen") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ChooseDatesSheet(today: previewToday, seed: nil, onDone: { _ in })
    }
}
#endif
