import SwiftUI

/// The colors along the top of a tracker's icon and color part (Figma 408:3745): the
/// four tracker hues, then five more, then any color at all.
enum TrackerColorPalette {
    static let swatches: [(name: String, hex: String)] = [
        ("Cyan", "#1c8fe0"), ("Teal", "#0d8c86"), ("Violet", "#6f5fe0"), ("Blue", "#5b76b3"),
        ("Green", "#2e9e5b"), ("Pink", "#d24f8c"), ("Indigo", "#4a55c4"), ("Brown", "#8b6b4e"),
        ("Graphite", "#5e6b7a"),
    ]

    /// Whether `hex` is one of the swatches; any other color shows on the any-color well.
    static func isSwatch(_ hex: String) -> Bool {
        swatches.contains { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    /// `#rrggbb` for a color picked from the iPhone's color picker.
    static func hex(_ color: Color) -> String { "#" + color.hexRGB }
}

/// A tracker's icon on its color: the preview beside its name, and the 64pt tile here.
struct TrackerIconTile: View {
    let icon: String
    let color: String
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(Color(hex: color))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// The icon and color part of Add tracker and Edit tracker (PRD "Add tracker": "colors
/// along the top, any color at all one tap beyond them, and the icons scrolling beneath,
/// chosen for care and searchable by name"). It is a part of the host's sheet, not a
/// sheet of its own: put it inside the sheet's NavigationStack and it supplies the title
/// and Done; Done calls `onDone` and the host shows its previous part again. Every tap
/// writes straight to the bindings, so the choice is made by the time Done is pressed.
struct TrackerIconColorPart: View {
    @Binding var icon: String
    /// `#rrggbb`.
    @Binding var color: String
    /// The tracker's name, shown under the preview.
    let name: String
    let onDone: () -> Void

    @State private var query = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 11), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.md)
                label("COLOR").padding(.top, 20).padding(.bottom, 10)
                colors
                label("ICON").padding(.top, 20).padding(.bottom, Theme.Spacing.sm)
                StrideField(placeholder: "Search icons", icon: "magnifyingglass", text: $query)
                icons.padding(.top, 12)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.surface)
        .navigationTitle("Icon and color")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone).fontWeight(.semibold)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TrackerIconTile(icon: icon, color: color)
            Text(name.isEmpty ? "New tracker" : name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    private var colors: some View {
        HStack(spacing: 0) {
            ForEach(TrackerColorPalette.swatches, id: \.hex) { swatch in
                Button { color = swatch.hex } label: {
                    swatchCircle(Color(hex: swatch.hex),
                                 selected: swatch.hex.caseInsensitiveCompare(color) == .orderedSame)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(swatch.hex.caseInsensitiveCompare(color) == .orderedSame ? .isSelected : [])
                Spacer(minLength: 0)
            }
            ColorPicker("Any color", selection: Binding(
                get: { Color(hex: color) },
                set: { color = TrackerColorPalette.hex($0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32, height: 32)
            .overlay {
                if !TrackerColorPalette.isSwatch(color) {
                    Circle().stroke(Color(hex: color), lineWidth: 2).frame(width: 34, height: 34)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func swatchCircle(_ fill: Color, selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle().stroke(fill, lineWidth: 2).frame(width: 30, height: 30)
                Circle().fill(fill).frame(width: 22, height: 22)
            } else {
                Circle().fill(fill).frame(width: 28, height: 28)
            }
        }
        .frame(width: 32, height: 32)
        .contentShape(Circle())
    }

    @ViewBuilder private var icons: some View {
        let groups = TrackerIconCatalog.groups(matching: query)
        if groups.isEmpty {
            Text("No icons match “\(query)”.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.vertical, Theme.Spacing.md)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    label(group.title.uppercased()).padding(.bottom, Theme.Spacing.sm)
                    LazyVGrid(columns: columns, spacing: 11) {
                        ForEach(group.icons, id: \.name) { item in
                            iconButton(item.name)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func iconButton(_ name: String) -> some View {
        let selected = name == icon
        return Button { icon = name } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color(hex: color) : Theme.Colors.surface)
                .overlay {
                    if !selected {
                        RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.border, lineWidth: 1)
                    }
                }
                .overlay {
                    Image(systemName: name)
                        .font(.system(size: 19))
                        .foregroundStyle(selected ? .white : Theme.Colors.textSecondary)
                }
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Blood pressure") {
    @Previewable @State var icon = TrackersFixtures.bloodPressure.icon
    @Previewable @State var color = TrackersFixtures.bloodPressure.color
    NavigationStack {
        TrackerIconColorPart(icon: $icon, color: $color, name: TrackersFixtures.bloodPressure.name, onDone: {})
    }
}

#Preview("Any color") {
    @Previewable @State var icon = "toilet"
    @Previewable @State var color = "#92400E"
    NavigationStack {
        TrackerIconColorPart(icon: $icon, color: $color, name: "Bowel Movement", onDone: {})
    }
}
#endif
