import SwiftUI

/// One day in a month calendar (Figma `Stride/Calendar Day` 513:999). The band
/// draws a continuous stretch between a range start and end; today is ringed;
/// disabled marks days that cannot be picked. Fills its column's width, 44 tall.
struct StrideCalendarDay: View {
    enum State: Equatable, Sendable {
        case `default`
        case inRange
        case rangeStart
        case rangeEnd
        /// A stretch of one day: the emphasized end, with no band. Not a Figma variant.
        case single
        case disabled
        case today
    }

    let day: Int
    var state: State = .default

    var body: some View {
        ZStack {
            band
            Text("\(day)")
                .font(.system(size: 15, weight: isEmphasized || state == .today ? .semibold : .medium))
                .foregroundStyle(textColor)
                .opacity(state == .disabled ? 0.55 : 1)
                .frame(width: 36, height: 36)
                .background {
                    if isEmphasized {
                        Circle().fill(Theme.Colors.accent)
                    } else if state == .today {
                        Circle().strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .accessibilityAddTraits(isEmphasized || state == .inRange ? .isSelected : [])
    }

    /// Half a column wide at either end, so the band meets the end's circle.
    @ViewBuilder
    private var band: some View {
        switch state {
        case .inRange:
            Theme.Colors.accentTint.frame(height: 36)
        case .rangeStart:
            HStack(spacing: 0) {
                Color.clear
                Theme.Colors.accentTint
            }
            .frame(height: 36)
        case .rangeEnd:
            HStack(spacing: 0) {
                Theme.Colors.accentTint
                Color.clear
            }
            .frame(height: 36)
        default:
            EmptyView()
        }
    }

    private var isEmphasized: Bool {
        state == .rangeStart || state == .rangeEnd || state == .single
    }

    private var textColor: Color {
        switch state {
        case .rangeStart, .rangeEnd, .single: Theme.Colors.textOnAccent
        case .today: Theme.Colors.accent
        case .disabled: Theme.Colors.textTertiary
        case .default, .inRange: Theme.Colors.textPrimary
        }
    }
}

#Preview("Variants") {
    VStack(spacing: Theme.Spacing.md) {
        HStack(spacing: 0) {
            StrideCalendarDay(day: 1)
            StrideCalendarDay(day: 2, state: .rangeStart)
            StrideCalendarDay(day: 3, state: .inRange)
            StrideCalendarDay(day: 4, state: .rangeEnd)
            StrideCalendarDay(day: 8, state: .today)
            StrideCalendarDay(day: 9, state: .disabled)
            StrideCalendarDay(day: 12, state: .single)
        }
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.surface)
}
