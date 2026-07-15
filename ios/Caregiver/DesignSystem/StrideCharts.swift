import Charts
import SwiftUI

/// A dated sample for the Stride charts. `value` is metric-defined: a reading for
/// the line chart, an hour-of-day (0–24) for the scatter, a count for the bars.
struct StrideChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// One named line on `StrideLineChart` (e.g. Systolic / Diastolic).
struct StrideChartSeries: Identifiable {
    let id = UUID()
    let name: String
    let hue: Color
    let points: [StrideChartPoint]
}

// MARK: - Shared chrome

/// Card + axis treatment shared by the three chart components (Figma
/// `Stride/Chart/*`): surface card (radius 14, 16pt padding), horizontal-only
/// `border` gridlines, 10pt `textTertiary` labels on both axes.
private struct StrideChartCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            }
    }
}

private func strideYAxis(values: AxisMarkValues = .automatic(desiredCount: 4)) -> some AxisContent {
    AxisMarks(position: .leading, values: values) {
        AxisGridLine()
            .foregroundStyle(Theme.Colors.border)
        AxisValueLabel()
            .font(.system(size: 10))
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

// MARK: - Line

/// Value-vs-time line chart (Figma `Stride/Chart/Line`): one `LineMark` per series
/// with a glowing dot on each latest point, a gradient area fill under the first
/// series, and a custom dot legend (Charts' own legend is hidden — it can't match
/// the Aurora treatment).
struct StrideLineChart: View {
    let series: [StrideChartSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ForEach(series) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.hue).frame(width: 8, height: 8)
                        Text(s.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            Chart {
                if let first = series.first {
                    ForEach(first.points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [first.hue.opacity(0.22), first.hue.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
                ForEach(series) { s in
                    ForEach(s.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value),
                            series: .value("Series", s.name)
                        )
                        .foregroundStyle(s.hue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let last = s.points.last {
                        PointMark(
                            x: .value("Date", last.date),
                            y: .value("Value", last.value)
                        )
                        .symbol {
                            Circle()
                                .fill(s.hue)
                                .frame(width: 9, height: 9)
                                .shadow(color: s.hue.opacity(0.9), radius: 4)
                        }
                    }
                }
            }
            .chartYAxis { strideYAxis() }
            .chartLegend(.hidden)
            .frame(height: 150)
        }
        .modifier(StrideChartCard())
    }
}

// MARK: - Scatter

/// Hour-of-day × date scatter (Figma `Stride/Chart/Scatter`) — the adherence view:
/// point `value` = hour (0–24), midnight at the top like the Figma plot, labels
/// 12a · 6a · 12p · 6p. The latest date's points draw bigger with a glow.
struct StrideScatterChart: View {
    let points: [StrideChartPoint]
    let hue: Color

    private var latestDate: Date? { points.map(\.date).max() }

    var body: some View {
        Chart(points) { point in
            let isLatest = point.date == latestDate
            PointMark(
                x: .value("Date", point.date),
                y: .value("Hour", point.value)
            )
            .symbol {
                Circle()
                    .fill(hue.opacity(isLatest ? 1 : 0.8))
                    .frame(width: isLatest ? 9 : 7, height: isLatest ? 9 : 7)
                    .shadow(color: isLatest ? hue.opacity(0.9) : .clear, radius: 4)
            }
        }
        .chartYScale(domain: [24, 0])
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 6, 12, 18]) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.border)
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(["12a", "6a", "12p", "6p"][hour / 6])
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .frame(height: 150)
        .modifier(StrideChartCard())
    }
}

// MARK: - Bar

/// Count-per-bucket bar trend (Figma `Stride/Chart/Bar`): hue bars with 4pt top
/// radii. Known drift: the Figma glows the latest bar; `BarMark` can't take a
/// per-mark shadow, so the latest bar draws at full hue and the rest slightly
/// dimmed instead.
struct StrideBarChart: View {
    let points: [StrideChartPoint]
    let hue: Color

    private var latestDate: Date? { points.map(\.date).max() }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Date", point.date, unit: .weekOfYear),
                y: .value("Count", point.value)
            )
            .foregroundStyle(hue.opacity(point.date == latestDate ? 1 : 0.85))
            .cornerRadius(4)
        }
        .chartYAxis { strideYAxis(values: .automatic(desiredCount: 3)) }
        .frame(height: 150)
        .modifier(StrideChartCard())
    }
}

// MARK: - Previews

private let previewDays: [Date] = (0..<28).map {
    Calendar.current.date(byAdding: .day, value: -27 + $0, to: .now)!
}

#Preview("Line — BP") {
    StrideLineChart(series: [
        StrideChartSeries(
            name: "Systolic", hue: Theme.Colors.trackerCyan,
            points: previewDays.enumerated().filter { $0.offset % 2 == 0 }.map {
                StrideChartPoint(date: $0.element, value: 124 + Double(($0.offset * 7) % 14))
            }
        ),
        StrideChartSeries(
            name: "Diastolic", hue: Theme.Colors.trackerTeal,
            points: previewDays.enumerated().filter { $0.offset % 2 == 0 }.map {
                StrideChartPoint(date: $0.element, value: 78 + Double(($0.offset * 5) % 10))
            }
        ),
    ])
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Scatter — adherence") {
    StrideScatterChart(
        points: previewDays.flatMap { day in
            [StrideChartPoint(date: day, value: 8 + Double(day.hashValue % 3)),
             StrideChartPoint(date: day, value: 19 + Double(day.hashValue % 2))]
        },
        hue: Theme.Colors.trackerViolet
    )
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("Bar — weekly counts") {
    StrideBarChart(
        points: [8, 12, 9, 13, 10].enumerated().map { index, count in
            StrideChartPoint(
                date: Calendar.current.date(byAdding: .weekOfYear, value: -4 + index, to: .now)!,
                value: Double(count)
            )
        },
        hue: Theme.Colors.trackerCyan
    )
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
