import SwiftUI

/// Who is on duty for a care receiver right now (Figma `Stride/Coverage Row` 247:1088):
/// a green dot, "Trevor is on duty", and until when. Coordination only — it never gates
/// logging — and absent entirely for a team that keeps no roster.
struct StrideCoverageRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.Colors.success)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background { Capsule().fill(Theme.Colors.successTint) }
        .accessibilityElement(children: .combine)
    }
}

/// Seven weekday circles, Sunday first, for a rule's days (Figma "Weekdays": a tracker's
/// schedule 375:3532 and a coverage schedule 451:3791).
struct StrideWeekdayPicker: View {
    let selected: Set<ScheduleWeekday>
    var size: CGFloat = 40
    let toggle: (ScheduleWeekday) -> Void

    private static let week: [ScheduleWeekday] = [.su, .mo, .tu, .we, .th, .fr, .sa]
    private static let letters: [ScheduleWeekday: String] = [.su: "S", .mo: "M", .tu: "T", .we: "W",
                                                             .th: "T", .fr: "F", .sa: "S"]
    private static let names: [ScheduleWeekday: String] = [.su: "Sunday", .mo: "Monday", .tu: "Tuesday",
                                                           .we: "Wednesday", .th: "Thursday",
                                                           .fr: "Friday", .sa: "Saturday"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.week.enumerated()), id: \.offset) { i, day in
                if i > 0 { Spacer(minLength: 4) }
                button(day)
            }
        }
    }

    private func button(_ day: ScheduleWeekday) -> some View {
        let on = selected.contains(day)
        return Button { toggle(day) } label: {
            Text(Self.letters[day] ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Theme.Colors.textOnAccent : Theme.Colors.textSecondary)
                .frame(width: size, height: size)
                .background { Circle().fill(on ? Theme.Colors.accent : Theme.Colors.surface) }
                .overlay { Circle().stroke(on ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.names[day] ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 16) {
        StrideCoverageRow(title: "Trevor is on duty", detail: "until 4:00 PM")
        StrideWeekdayPicker(selected: [.tu], size: 42) { _ in }
    }
    .padding(24)
}
#endif
