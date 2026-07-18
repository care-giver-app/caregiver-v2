import XCTest
@testable import Caregiver

final class ScheduleTimeTests: XCTestCase {
    // Fixed gregorian calendar in a fixed zone so the math is deterministic.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: relativeLabel

    func testRelativeLabelLaterTodayIsToday() {
        let now = date(2026, 7, 16, 9)
        XCTAssertEqual(ScheduleTime.relativeLabel(to: date(2026, 7, 16, 10), now: now, calendar: cal), "Today")
        XCTAssertEqual(ScheduleTime.relativeLabel(to: date(2026, 7, 16, 23), now: now, calendar: cal), "Today")
    }

    func testRelativeLabelTomorrow() {
        let now = date(2026, 7, 16, 9)
        XCTAssertEqual(ScheduleTime.relativeLabel(to: date(2026, 7, 17, 8), now: now, calendar: cal), "Tomorrow")
    }

    func testRelativeLabelInDays() {
        let now = date(2026, 7, 16, 9)
        XCTAssertEqual(ScheduleTime.relativeLabel(to: date(2026, 7, 25, 9), now: now, calendar: cal), "in 9 days")
        XCTAssertEqual(ScheduleTime.relativeLabel(to: date(2026, 8, 25, 9), now: now, calendar: cal), "in 40 days")
    }

    func testRelativeLabelOverdue() {
        let now = date(2026, 7, 16, 9)
        XCTAssertEqual(ScheduleTime.relativeLabel(to: date(2026, 7, 15, 23), now: now, calendar: cal), "Overdue")
    }

    // MARK: bucket

    func testBucketThisWeekThroughSixDays() {
        let now = date(2026, 7, 16, 9)
        XCTAssertEqual(ScheduleTime.bucket(for: date(2026, 7, 16, 20), now: now, calendar: cal), .thisWeek) // today
        XCTAssertEqual(ScheduleTime.bucket(for: date(2026, 7, 17, 9), now: now, calendar: cal), .thisWeek)  // tomorrow
        XCTAssertEqual(ScheduleTime.bucket(for: date(2026, 7, 22, 9), now: now, calendar: cal), .thisWeek)  // 6 days
    }

    func testBucketLaterFromSevenDays() {
        let now = date(2026, 7, 16, 9)
        XCTAssertEqual(ScheduleTime.bucket(for: date(2026, 7, 23, 9), now: now, calendar: cal), .later) // 7 days
        XCTAssertEqual(ScheduleTime.bucket(for: date(2026, 8, 9, 9), now: now, calendar: cal), .later)
    }
}
