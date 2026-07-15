import SwiftUI

enum StrideBadgeStatus {
    case failure, warning, informational, success, muted

    var color: Color {
        switch self {
        case .failure:       return Theme.Colors.alert
        case .warning:       return Theme.Colors.warning
        case .informational: return Theme.Colors.informational
        case .success:       return Theme.Colors.success
        case .muted:         return Theme.Colors.muted
        }
    }
}

enum StrideBadgeStyle { case tinted, filled, outlined }

struct StrideBadge: View {
    let status: StrideBadgeStatus
    var style: StrideBadgeStyle = .tinted
    var icon: String? = nil
    let label: String

    // Figma `Stride/Status Badge` (90:78): 11pt semibold on a 15% tint, radius 8.
    private static let shape = RoundedRectangle(cornerRadius: 8)

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(label)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .foregroundStyle(style == .filled ? Color.white : status.color)
        .background {
            switch style {
            case .tinted:   Self.shape.fill(status.color.opacity(0.15))
            case .filled:   Self.shape.fill(status.color)
            case .outlined: Self.shape.fill(Color.clear)
            }
        }
        .overlay {
            if style == .outlined {
                Self.shape.stroke(status.color, lineWidth: 1.5)
            }
        }
    }
}

#Preview("Status × style") {
    Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.sm, verticalSpacing: Theme.Spacing.sm) {
        GridRow {
            StrideBadge(status: .warning, label: "Due")
            StrideBadge(status: .warning, style: .filled, label: "Due")
            StrideBadge(status: .warning, style: .outlined, label: "Due")
        }
        GridRow {
            StrideBadge(status: .failure, label: "Missed")
            StrideBadge(status: .success, label: "Logged")
            StrideBadge(status: .informational, icon: "calendar", label: "Upcoming")
        }
    }
    .padding(Theme.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}
