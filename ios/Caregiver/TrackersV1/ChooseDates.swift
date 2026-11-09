import Foundation

/// A calendar day with no time and no zone — what a day in the receiver's zone is
/// once it has been read there. Day arithmetic on it never touches a zone, so a
/// DST change cannot make a day 23 or 25 hours long.
struct LocalDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `zone`.
    init(_ date: Date, zone: TimeZone) {
        var calendar = LocalDay.gregorian
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// `yyyy-MM-dd` — the shape `EntryDateRange` takes.
    var dayString: String { String(format: "%04d-%02d-%02d", year, month, day) }

    func adding(days: Int) -> LocalDay {
        let moved = LocalDay.utc.date(byAdding: .day, value: days, to: utcDate)!
        return LocalDay(moved, zone: LocalDay.utc.timeZone)
    }

    /// Midnight starting this day in `zone`.
    func start(in zone: TimeZone) -> Date {
        var calendar = LocalDay.gregorian
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Weekday, 1 = Sunday … 7 = Saturday.
    var weekday: Int { LocalDay.utc.component(.weekday, from: utcDate) }

    private var utcDate: Date { start(in: LocalDay.utc.timeZone) }

    private static let gregorian = Calendar(identifier: .gregorian)
    fileprivate static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

/// A month of the calendar.
struct CalendarMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ day: LocalDay) {
        self.init(year: day.year, month: day.month)
    }

    static func < (a: CalendarMonth, b: CalendarMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }

    var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    var next: CalendarMonth {
        month == 12 ? CalendarMonth(year: year + 1, month: 1) : CalendarMonth(year: year, month: month + 1)
    }

    var firstDay: LocalDay { LocalDay(year: year, month: month, day: 1) }

    var dayCount: Int {
        let start = firstDay.start(in: LocalDay.utc.timeZone)
        return LocalDay.utc.range(of: .day, in: .month, for: start)!.count
    }

    /// The month's weeks, Sunday first; nil where a week runs into the month
    /// before or after.
    var weeks: [[LocalDay?]] {
        let lead = firstDay.weekday - 1
        var cells: [LocalDay?] = Array(repeating: nil, count: lead)
        cells += (1...dayCount).map { LocalDay(year: year, month: month, day: $0) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

/// What Tracker detail's entries are narrowed to (PRD "Tracker detail": the chips).
/// All on open, every time — the choice is not remembered.
enum EntryWindow: Equatable, Sendable {
    case all
    case last7
    case last30
    case custom(first: LocalDay, last: LocalDay)

    /// The stretch to ask for, given today in the receiver's zone. 7 days is today
    /// and the six before it; 30 days, today and the 29 before.
    func range(today: LocalDay) -> EntryDateRange? {
        switch self {
        case .all: nil
        case .last7: EntryDateRange(from: today.adding(days: -6).dayString, to: today.dayString)
        case .last30: EntryDateRange(from: today.adding(days: -29).dayString, to: today.dayString)
        case .custom(let first, let last): EntryDateRange(from: first.dayString, to: last.dayString)
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// The custom stretch, when there is one — what Choose dates opens on.
    var customStretch: (first: LocalDay, last: LocalDay)? {
        if case .custom(let first, let last) = self { return (first, last) }
        return nil
    }

    /// "Nov 2 – Nov 7"; "Nov 2" for one day; the year shown outside today's.
    static func stretchLabel(first: LocalDay, last: LocalDay, today: LocalDay) -> String {
        func short(_ d: LocalDay) -> String {
            let name = monthAbbreviations[d.month - 1]
            return d.year == today.year ? "\(name) \(d.day)" : "\(name) \(d.day), \(d.year)"
        }
        return first == last ? short(first) : "\(short(first)) – \(short(last))"
    }

    private static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

/// One chip under ENTRIES.
enum EntryWindowChip: CaseIterable, Sendable {
    case all, last7, last30, custom

    /// The chip's words; Custom reads the stretch while one is chosen (Figma 514:934).
    func label(for window: EntryWindow, today: LocalDay) -> String {
        switch self {
        case .all: return "All"
        case .last7: return "7 days"
        case .last30: return "30 days"
        case .custom:
            guard let stretch = window.customStretch else { return "Custom" }
            return EntryWindow.stretchLabel(first: stretch.first, last: stretch.last, today: today)
        }
    }

    func isSelected(by window: EntryWindow) -> Bool {
        switch (self, window) {
        case (.all, .all), (.last7, .last7), (.last30, .last30), (.custom, .custom): true
        default: false
        }
    }
}

/// Choose dates — a month calendar in the receiver's zone where a first and a last
/// day are tapped (PRD "Choose dates"). Pure: `today` is passed in.
struct ChooseDatesModel: Equatable, Sendable {
    let today: LocalDay
    private(set) var month: CalendarMonth
    private(set) var first: LocalDay?
    private(set) var last: LocalDay?

    /// Opens on the current custom stretch's month when there is one, else this month.
    init(today: LocalDay, seed: (first: LocalDay, last: LocalDay)? = nil) {
        self.today = today
        first = seed?.first
        last = seed?.last
        month = CalendarMonth(seed?.last ?? today)
    }

    // MARK: Months

    /// Earlier months are always there.
    var canGoBack: Bool { true }
    /// Forward again, as far as this month.
    var canGoForward: Bool { month < CalendarMonth(today) }

    mutating func goBack() { month = month.previous }

    mutating func goForward() {
        guard canGoForward else { return }
        month = month.next
    }

    // MARK: Picking

    /// Entries still to come are not in the list, so days after today cannot be picked.
    func isDisabled(_ day: LocalDay) -> Bool { day > today }

    /// The first tap picks the first day; the second, the last (an earlier day
    /// swaps them); a third starts over.
    mutating func tap(_ day: LocalDay) {
        guard !isDisabled(day) else { return }
        switch (first, last) {
        case (let first?, nil):
            if day < first {
                self.first = day
                last = first
            } else {
                last = day
            }
        default:
            first = day
            last = nil
        }
    }

    mutating func clear() {
        first = nil
        last = nil
    }

    /// The stretch as picked so far; a lone first day is a one-day stretch.
    var stretch: (first: LocalDay, last: LocalDay)? {
        guard let first else { return nil }
        return (first, last ?? first)
    }

    /// "Nov 2 – Nov 7", or nil with nothing chosen.
    var stretchLabel: String? {
        stretch.map { EntryWindow.stretchLabel(first: $0.first, last: $0.last, today: today) }
    }

    /// What Done applies: the stretch, or All when nothing is chosen.
    var outcome: EntryWindow {
        guard let stretch else { return .all }
        return .custom(first: stretch.first, last: stretch.last)
    }

    // MARK: Drawing

    func state(of day: LocalDay) -> StrideCalendarDay.State {
        if let stretch {
            if stretch.first == stretch.last, day == stretch.first { return .single }
            if day == stretch.first { return .rangeStart }
            if day == stretch.last { return .rangeEnd }
            if day > stretch.first, day < stretch.last { return .inRange }
        }
        if isDisabled(day) { return .disabled }
        if day == today { return .today }
        return .default
    }
}
