import SwiftUI

/// One entry on Tracker detail (Figma Stride/Entry Tile 432:3260): when, its state,
/// every field value it carries, its note, and who logged or skipped it.
///
/// TODO(Home build): the whole tile opens Entry detail, which Home's build brings.
/// Until then it is not tappable and carries no chevron, so it does not promise a tap.
struct EntryTileV1: View {
    let entry: TrackerEntry
    let fields: [TrackerFieldInfo]
    let zone: TimeZone
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(TrackerText.when(entry.at, now: now, zone: zone))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 1)
                badge
            }

            let rows = TrackerText.valueRows(entry, fields: fields, now: now, zone: zone)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Spacer(minLength: 1)
                            Text(row.value)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.system(size: 14))
                    }
                }
            }

            if let note = entry.note, !note.isEmpty {
                Text("\u{201C}\(note)\u{201D}")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let byline = TrackerText.byline(entry) {
                Text(byline)
                    .font(.system(size: entry.state == .unrecorded ? 14 : 13))
                    .foregroundStyle(entry.state == .unrecorded ? Theme.Colors.textSecondary
                                                                : Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    /// Figma 432:3223 / 432:3246 / 432:3255.
    private var badge: some View {
        let label = TrackerText.stateLabel(entry.state)
        let (fg, bg): (Color, Color) = switch entry.state {
        case .logged: (Theme.Colors.success, Color(hex: "dcefe6"))
        case .unrecorded: (Theme.Colors.alert, Color(hex: "f9e0e5"))
        case .skipped, .scheduled: (Theme.Colors.textTertiary, Theme.Colors.surfaceHi)
        }
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background { RoundedRectangle(cornerRadius: 8).fill(bg) }
    }
}

#if DEBUG
#Preview("States") {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(TrackersFixtures.medicationEntries) { entry in
                EntryTileV1(entry: entry, fields: TrackersFixtures.medicationFields,
                            zone: TrackersFixtures.eleanor.timeZone, now: Date())
            }
        }
        .padding(Theme.Spacing.lg)
    }
    .strideBackground()
}
#endif
