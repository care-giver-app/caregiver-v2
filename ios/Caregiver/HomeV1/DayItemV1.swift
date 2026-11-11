import SwiftUI

/// One tile of Home's daily timeline (Figma `Stride/Day Item` 435:3933, Kind = Logged |
/// Unrecorded | Skipped | Note): the tracker's hue tile and icon, its name and time, a
/// badge only when unrecorded or skipped, then what the entry holds and who logged it.
/// A note has a violet Doc tile, its body and its author.
struct DayItemV1: View {
    let item: DayItem
    /// The entry's tracker's fields, when known, so values can be labeled.
    let fields: [TrackerFieldInfo]?
    let zone: TimeZone
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item {
            case .entry(let e): entry(e)
            case .note(let n): note(n)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func entry(_ e: ReceiverEntryItem) -> some View {
        header(title: e.tracker.name, time: HomeText.itemTime(e.entry, zone: zone),
               badge: badge(e.entry.state)) {
            tile(fill: Color(hex: e.tracker.color)) {
                Image(systemName: e.tracker.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white)
            }
        }

        if e.entry.state == .logged, let fields {
            let shown = fields.filter { field in
                e.entry.values[field.id].flatMap {
                    TrackerText.value($0, field: field, now: now, zone: zone)
                } != nil
            }
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shown, id: \.id) { field in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(field.label)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Spacer(minLength: 1)
                            Text(e.entry.values[field.id].flatMap {
                                TrackerText.value($0, field: field, now: now, zone: zone)
                            } ?? "")
                            .fontWeight(.medium)
                            .foregroundStyle(HomeText.isOutOfRange(e.entry, field: field)
                                             ? Theme.Colors.alert : Theme.Colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                        }
                        .font(.system(size: 14))
                    }
                }
            }
        }

        if let note = e.entry.note, !note.isEmpty {
            Text(note)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let byline = TrackerText.byline(e.entry) {
            Text(byline)
                .font(.system(size: e.entry.state == .unrecorded ? 14 : 13))
                .foregroundStyle(e.entry.state == .unrecorded ? Theme.Colors.textSecondary
                                                               : Theme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private func note(_ n: JournalNoteInfo) -> some View {
        header(title: "Journal note", time: HomeText.clock(n.at, zone: zone), badge: nil) {
            tile(fill: Theme.Colors.violetTint) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.trackerViolet)
            }
        }
        Text(n.body)
            .font(.system(size: 15))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(HomeText.noteByline(n))
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    private func header<Tile: View>(title: String, time: String, badge: AnyView?,
                                    @ViewBuilder tile: () -> Tile) -> some View {
        HStack(spacing: 10) {
            tile()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(time)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 1)
            badge
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func tile<Icon: View>(fill: Color, @ViewBuilder icon: () -> Icon) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(fill)
            .frame(width: 32, height: 32)
            .overlay { icon() }
            .accessibilityHidden(true)
    }

    /// Only the two states that say something went other than planned carry one.
    private func badge(_ state: EntryState) -> AnyView? {
        let (fg, bg): (Color, Color)
        switch state {
        case .unrecorded: (fg, bg) = (Theme.Colors.alert, Theme.Colors.alertTint)
        case .skipped: (fg, bg) = (Theme.Colors.textTertiary, Theme.Colors.surfaceHi)
        case .logged, .scheduled: return nil
        }
        return AnyView(
            Text(TrackerText.stateLabel(state))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 3)
                .background { RoundedRectangle(cornerRadius: 8).fill(bg) }
        )
    }
}

#if DEBUG
#Preview("Kinds") {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(HomeFixtures.yesterdayTimeline.items) { item in
                let fields: [TrackerFieldInfo]? = switch item {
                case .entry(let e): e.tracker.id == "bp" ? HomeFixtures.bloodPressureFields
                    : TrackersFixtures.medicationFields
                case .note: nil
                }
                DayItemV1(item: item, fields: fields, zone: HomeFixtures.chicago, now: Date())
            }
        }
        .padding(Theme.Spacing.lg)
    }
    .strideBackground()
}
#endif
