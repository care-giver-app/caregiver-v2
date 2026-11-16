import SwiftUI

enum StrideTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case insights = "Insights"
    case team = "Team"
    case settings = "Settings"

    var id: String { rawValue }
    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .insights: "chart.bar"
        case .team: "person.2"
        case .settings: "gearshape"
        }
    }
}

struct StrideTabBar: View {
    @Binding var selection: StrideTab
    let onQuickLog: () -> Void

    /// Rendered height of the bar, so pushed views can clear it explicitly — it sits
    /// as a persistent `safeAreaInset` on the root `TabView`, which pushed
    /// `navigationDestination` content doesn't automatically account for.
    static let reservedHeight = Metrics.barHeight

    /// What a screen under the bar leaves clear at its bottom: the bar, the ⊕ button's
    /// overhang above it, and a gap, so a button pinned to the screen's bottom ends clear
    /// of the ⊕ as well as the bar.
    static let clearance = Metrics.barHeight + Metrics.fabOverhang + Theme.Spacing.sm

    /// The bar drawn over a tab container's content, bottom-aligned. It is an overlay
    /// rather than a `safeAreaInset` because SwiftUI does not pass a TabView's or a
    /// NavigationStack's bottom inset to screens pushed on the stack; each screen clears
    /// the bar itself with `strideTabBarClearance()` instead, so every screen — root or
    /// pushed — is measured the same way and nothing pinned to its bottom sits under it.

    private enum Metrics {
        static let barHeight: CGFloat = 60
        static let iconSize: CGFloat = 24
        static let fabSlotWidth: CGFloat = 40
        static let fabSize: CGFloat = 58
        static let fabOverhang: CGFloat = 14
    }

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.insights)
            Color.clear.frame(width: Metrics.fabSlotWidth)
            tabButton(.team)
            tabButton(.settings)
        }
        .padding(.top, Theme.Spacing.sm)
        .frame(height: Metrics.barHeight)
        .frame(maxWidth: .infinity)
        .background { Theme.Colors.surface.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.border)
                .frame(height: 1)
        }
        .overlay(alignment: .top) {
            fab.offset(y: -Metrics.fabOverhang)
        }
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: StrideTab) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: Metrics.iconSize)
                Text(tab.title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Theme.Colors.accent : Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
    }

    private var fab: some View {
        Button(action: onQuickLog) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent)
                    .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 7, x: 0, y: 4)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textOnAccent)
            }
            .frame(width: Metrics.fabSize, height: Metrics.fabSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick log")
    }
}

#Preview("In context") {
    @Previewable @State var selection: StrideTab = .home
    VStack(spacing: 0) {
        Spacer()
        Text(selection.title)
            .font(Theme.Typography.title)
            .foregroundStyle(Theme.Colors.textPrimary)
        Spacer()
        StrideTabBar(selection: $selection) {}
    }
    .background { Theme.Colors.background.ignoresSafeArea() }
}

#Preview("All states") {
    VStack(spacing: Theme.Spacing.lg) {
        ForEach(StrideTab.allCases) { tab in
            StrideTabBar(selection: .constant(tab)) {}
        }
    }
    .padding(.vertical, Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Theme.Colors.background.ignoresSafeArea() }
}

extension View {
    /// Reserves the tab bar's height at the bottom of this screen's safe area, so its
    /// scroll content and anything it pins to its bottom (`safeAreaInset`) end above the
    /// bar. Apply to every screen shown under `StrideTabBar` — each tab's root and every
    /// pushed destination — and never twice on one screen.
    func strideTabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: StrideTabBar.clearance)
        }
    }
}
