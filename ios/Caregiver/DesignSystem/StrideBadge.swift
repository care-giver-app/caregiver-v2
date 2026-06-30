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

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(label)
        }
        .font(Theme.Typography.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .foregroundStyle(style == .filled ? Color.white : status.color)
        .background {
            switch style {
            case .tinted:   Capsule().fill(status.color.opacity(0.15))
            case .filled:   Capsule().fill(status.color)
            case .outlined: Capsule().fill(Color.clear)
            }
        }
        .overlay {
            if style == .outlined {
                Capsule().stroke(status.color, lineWidth: 1.5)
            }
        }
    }
}
