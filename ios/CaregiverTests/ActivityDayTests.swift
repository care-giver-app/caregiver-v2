import XCTest
@testable import Caregiver

final class ActivityDayTests: XCTestCase {
    // Fixed gregorian calendar in a fixed zone so the math is deterministic.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    func testBoundsAreStartOfDayToNextMidnight() {
        // 2026-06-17 14:30 America/Chicago
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 14, minute: 30))!
        let b = ActivityDay.bounds(for: date, calendar: cal)
        XCTAssertEqual(b.start, cal.date(from: DateComponents(year: 2026, month: 6, day: 17))!)
        XCTAssertEqual(b.end, cal.date(from: DateComponents(year: 2026, month: 6, day: 18))!)
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 24 * 60 * 60, accuracy: 1)
    }

    func testLabelToday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!
        let same = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 20))!
        XCTAssertEqual(ActivityDay.label(for: same, relativeTo: now, calendar: cal), "Today")
    }

    func testLabelYesterday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!
        let prev = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 23))!
        XCTAssertEqual(ActivityDay.label(for: prev, relativeTo: now, calendar: cal), "Yesterday")
    }

    func testLabelOlderUsesWeekdayAndDate() {
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!
        let older = cal.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 9))!
        // 2026-06-14 is a Sunday.
        XCTAssertEqual(ActivityDay.label(for: older, relativeTo: now, calendar: cal), "Sun, Jun 14")
    }

    func testIsDaytimeFalseJustBeforeSix() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 5, minute: 59))!
        XCTAssertFalse(ActivityDay.isDaytime(d, calendar: cal))
    }

    func testIsDaytimeTrueAtSix() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 6))!
        XCTAssertTrue(ActivityDay.isDaytime(d, calendar: cal))
    }

    func testIsDaytimeTrueJustBeforeEighteen() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 17, minute: 59))!
        XCTAssertTrue(ActivityDay.isDaytime(d, calendar: cal))
    }

    func testIsDaytimeFalseAtEighteen() {
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 18))!
        XCTAssertFalse(ActivityDay.isDaytime(d, calendar: cal))
    }
}
