import SwiftUI

/// The analytics timeframes the Insights screen offers. Display order = declaration
/// order. What `.custom` triggers (a date-range sheet) belongs to the consumer —
/// the selector only reports selection.
enum StrideTimeframe: CaseIterable {
    case week, month, threeMonths, year, custom

    var label: String {
        switch self {
        case .week:        return "Week"
        case .month:       return "Month"
        case .threeMonths: return "3M"
        case .year:        return "Year"
        case .custom:      return "Custom"
        }
    }
}

/// A five-segment timeframe control (Figma `Stride/Timeframe Selector`): equal-width
/// segments on a surface track; the selected one is an accent pill with ink text.
/// Custom rather than `Picker(.segmented)` — the Aurora track/pill/typography can't
/// be reached through the system control (same rationale as `StrideTabBar`).
struct StrideTimeframeSelector: View {
    @Binding var selection: StrideTimeframe
    @Namespace private var pillNamespace

    private enum Metrics {
        static let height: CGFloat = 40
        static let trackRadius: CGFloat = 12
        static let segmentRadius: CGFloat = 9
        static let inset: CGFloat = 4
        static let segmentGap: CGFloat = 2
    }

    var body: some View {
        HStack(spacing: Metrics.segmentGap) {
            ForEach(StrideTimeframe.allCases, id: \.self) { timeframe in
                segment(for: timeframe)
            }
        }
        .padding(Metrics.inset)
        .frame(height: Metrics.height)
        .background {
            RoundedRectangle(cornerRadius: Metrics.trackRadius)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.trackRadius)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
    }

    private func segment(for timeframe: StrideTimeframe) -> some View {
        let isSelected = timeframe == selection
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = timeframe
            }
        } label: {
            Text(timeframe.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.Colors.textOnAccent : Theme.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Metrics.segmentRadius)
                            .fill(Theme.Colors.accent)
                            .matchedGeometryEffect(id: "pill", in: pillNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Default (Month)") {
    StrideTimeframeSelector(selection: .constant(.month))
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Interactive") {
    @Previewable @State var selection: StrideTimeframe = .week
    VStack(spacing: Theme.Spacing.lg) {
        StrideTimeframeSelector(selection: $selection)
        Text("Selected: \(selection.label)")
            .font(Theme.Typography.subhead)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
