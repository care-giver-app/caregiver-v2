import Foundation

/// Every sentence Home prints, as pure functions of their inputs. Times are read in the
/// care receiver's zone, never the device's, and `now` is passed in.
enum HomeText {
    /// What a caregiver who is not an admin is told when the receiver has no active
    /// trackers. Home, the Trackers list and Quick log all say it "in the same words Home
    /// uses" (PRD "The tab bar"), so it lives here once — Trevor chose the Trackers list's
    /// wording over Figma 438:4075's on 2026-11-11.
    static let noTrackersCaregiverLine = "An admin on the team can add the first one."
    static let noTrackersAdminLine = "Add a tracker to start keeping a record."
    static let noTrackersTitle = "Nothing is being tracked"

    static let noReceiversTitle = "No one to look after yet"
    static let noReceiversAdminLine = "Add the person this team cares for to start keeping their record."
    static let noReceiversCaregiverLine = "Waiting on an admin to add a care receiver."

    static let allClearTitle = "Nothing needs attention"
    static let allClearLine = "Every tracker is in range and up to date."

    static let emptyDayTitle = "Nothing on this day"
    static let emptyDayLine = "Nothing was logged and nothing was expected."

    // MARK: Needs attention

    /// The cause under the tracker's name (Figma 436:3226).
    static func attention(_ attention: NeedsAttention, now: Date, zone: TimeZone) -> String {
        switch attention {
        case .unrecorded(_, let at):
            return "Unrecorded · \(TrackerText.when(at, now: now, zone: zone))"
        case .outOfRange(_, _, let label, _, let value, let range):
            // Figma 436:3265 reads the numbers bare: "Systolic 168 · expected 90–140".
            return "\(label ?? "Reading") \(TrackerText.number(value)) · \(expected(range, unit: nil))"
        case .gap(let since, _):
            return "Nothing logged in \(TrackerText.gapElapsed(since: since, now: now))"
        }
    }

    /// "expected 90–140", "expected at most 140", "expected at least 90".
    static func expected(_ range: ValueRangeInfo, unit: String?) -> String {
        switch (range.low, range.high) {
        case let (low?, high?):
            "expected \(TrackerText.number(low))–\(withUnit(TrackerText.number(high), unit))"
        case let (nil, high?):
            "expected at most \(withUnit(TrackerText.number(high), unit))"
        case let (low?, nil):
            "expected at least \(withUnit(TrackerText.number(low), unit))"
        case (nil, nil):
            "outside its range"
        }
    }

    /// Whether an entry's value for `field` lies outside the field's range.
    static func isOutOfRange(_ entry: TrackerEntry, field: TrackerFieldInfo) -> Bool {
        guard entry.state == .logged, let range = field.range,
              case .number(let n)? = entry.values[field.id] else { return false }
        if let low = range.low, n < low { return true }
        if let high = range.high, n > high { return true }
        return false
    }

    // MARK: Coming up

    /// "Evening · Today at 8:00 PM", "Tomorrow at 2:00 PM", "Wednesday at 10:00 AM",
    /// "Nov 20 at 9:00 AM" (Figma 436:3290).
    static func comingUp(_ entry: TrackerEntry, now: Date, zone: TimeZone) -> String {
        let when = ahead(entry.at, now: now, zone: zone)
        guard let schedule = entry.scheduleName, !schedule.isEmpty else { return when }
        return "\(schedule) · \(when)"
    }

    static func ahead(_ date: Date, now: Date, zone: TimeZone) -> String {
        let days = LocalDay.daysBetween(LocalDay(now, zone: zone), LocalDay(date, zone: zone))
        let time = clock(date, zone: zone)
        let day: String
        switch days {
        case ...0: day = "Today"
        case 1: day = "Tomorrow"
        case 2...6: day = TrackerText.format(date, "EEEE", zone)
        default:
            let sameYear = LocalDay(date, zone: zone).year == LocalDay(now, zone: zone).year
            day = TrackerText.format(date, sameYear ? "MMM d" : "MMM d, yyyy", zone)
        }
        return "\(day) at \(time)"
    }

    // MARK: The timeline

    /// "Today" with "Sun, Oct 25"; any other day by its weekday, "Friday" with "Oct 23"
    /// (Figma 436:3307, 437:4143). The year joins outside today's.
    static func dayTitle(_ day: LocalDay, today: LocalDay) -> (title: String, detail: String) {
        let start = day.start(in: utc)
        let year = day.year == today.year ? "" : ", \(day.year)"
        if day == today {
            return ("Today", TrackerText.format(start, "EEE, MMM d", utc) + year)
        }
        return (TrackerText.format(start, "EEEE", utc), TrackerText.format(start, "MMM d", utc) + year)
    }

    /// "8:00 AM".
    static func clock(_ date: Date, zone: TimeZone) -> String {
        TrackerText.format(date, "h:mm a", zone)
    }

    /// "Morning · 8:00 AM", or "8:04 AM" when it came from no schedule.
    static func itemTime(_ entry: TrackerEntry, zone: TimeZone) -> String {
        let time = clock(entry.at, zone: zone)
        guard let schedule = entry.scheduleName, !schedule.isEmpty else { return time }
        return "\(schedule) · \(time)"
    }

    /// "Written by Dana".
    static func noteByline(_ note: JournalNoteInfo) -> String {
        "Written by \(note.authorName)"
    }

    // MARK: Coming up, the screen

    static let comingUpEmptyTitle = "Nothing is coming up"
    static let comingUpEmptyLine = "Everything that was scheduled has been logged or skipped."

    // MARK: Entry detail and Journal note

    /// Said where a pre-filled value is still to be given (Figma 445:4161).
    static let leftForLogger = "Left for whoever logs it"
    static let unrecordedCalloutTitle = "Needs attention"
    static let unrecordedCalloutLine = "Nothing was recorded for this time."
    static let outOfRangeTitle = "Out of range"
    static let entryGone = "This entry is no longer here. Someone may have deleted it."
    static let noteGone = "This note is no longer here. Someone may have deleted it."

    /// An entry's own time: ahead of now as Coming up says it, otherwise as Tracker detail does.
    static func entryWhen(_ date: Date, now: Date, zone: TimeZone) -> String {
        date > now ? ahead(date, now: now, zone: zone) : TrackerText.when(date, now: now, zone: zone)
    }

    /// "Systolic is 168 mmHg. It is expected to stay between 90 and 140." (Figma 445:4287)
    static func outOfRangeSentence(label: String, value: Double, unit: String?, range: ValueRangeInfo) -> String {
        let reading = "\(label) is \(withUnit(TrackerText.number(value), unit))."
        let expected: String
        switch (range.low, range.high) {
        case let (low?, high?):
            expected = "It is expected to stay between \(TrackerText.number(low)) and \(TrackerText.number(high))."
        case let (nil, high?):
            expected = "It is expected to stay at or below \(TrackerText.number(high))."
        case let (low?, nil):
            expected = "It is expected to stay at or above \(TrackerText.number(low))."
        case (nil, nil):
            return reading
        }
        return "\(reading) \(expected)"
    }

    /// "Expected 90–140", under a value outside its range (Figma 445:4298).
    static func expectedUnderValue(_ range: ValueRangeInfo) -> String {
        let text = expected(range, unit: nil)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Dana · 8:05 AM": who, and when — the clock alone on the day `about` falls on in
    /// the receiver's zone, otherwise the day as well. Nil with neither.
    static func whoAndWhen(_ name: String?, at: Date?, about: Date, now: Date, zone: TimeZone) -> String? {
        let when = at.map { at in
            LocalDay(at, zone: zone) == LocalDay(about, zone: zone)
                ? clock(at, zone: zone) : TrackerText.when(at, now: now, zone: zone)
        }
        let parts = [name, when].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let utc = TimeZone(identifier: "UTC")!

    private static func withUnit(_ value: String, _ unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }
}

extension LocalDay {
    /// Whole days from `a` to `b`; negative when `b` is earlier.
    static func daysBetween(_ a: LocalDay, _ b: LocalDay) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let utc = TimeZone(identifier: "UTC")!
        return calendar.dateComponents([.day], from: a.start(in: utc), to: b.start(in: utc)).day ?? 0
    }
}
