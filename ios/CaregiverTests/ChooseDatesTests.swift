import XCTest
@testable import Caregiver

/// Fixed instants, days and zones: nothing here reads the clock or the device zone.
private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d) }
private let chicago = TimeZone(identifier: "America/Chicago")!
private let utc = TimeZone(identifier: "UTC")!
/// Sunday Nov 8 2026 — today in the Figma frames.
private let nov8 = day(2026, 11, 8)

final class EntryWindowTests: XCTestCase {
    /// 03:00 UTC on Nov 3 is 9 PM on Nov 2 in Chicago — the receiver's today.
    private let instant = ISO8601DateFormatter().date(from: "2026-11-03T03:00:00Z")!

    func testTodayIsTheReceiversDay() {
        XCTAssertEqual(LocalDay(instant, zone: chicago), day(2026, 11, 2))
        XCTAssertEqual(LocalDay(instant, zone: utc), day(2026, 11, 3))
    }

    func testSevenDaysCrossesIntoTheMonthBefore() {
        let today = LocalDay(instant, zone: chicago)
        XCTAssertEqual(EntryWindow.last7.range(today: today),
                       EntryDateRange(from: "2026-10-27", to: "2026-11-02"))
    }

    func testThirtyDaysIsTodayAndTheTwentyNineBefore() {
        let today = LocalDay(instant, zone: chicago)
        XCTAssertEqual(EntryWindow.last30.range(today: today),
                       EntryDateRange(from: "2026-10-04", to: "2026-11-02"))
    }

    func testAllAsksForEverything() {
        XCTAssertNil(EntryWindow.all.range(today: nov8))
    }

    func testCustomAsksForItsStretch() {
        XCTAssertEqual(EntryWindow.custom(first: day(2026, 11, 2), last: day(2026, 11, 7)).range(today: nov8),
                       EntryDateRange(from: "2026-11-02", to: "2026-11-07"))
    }

    func testDayArithmeticCrossesAYear() {
        XCTAssertEqual(day(2027, 1, 3).adding(days: -6), day(2026, 12, 28))
    }

    func testChipLabels() {
        let custom = EntryWindow.custom(first: day(2026, 11, 2), last: day(2026, 11, 7))
        XCTAssertEqual(EntryWindowChip.allCases.map { $0.label(for: .all, today: nov8) },
                       ["All", "7 days", "30 days", "Custom"])
        XCTAssertEqual(EntryWindowChip.custom.label(for: custom, today: nov8), "Nov 2 – Nov 7")
        XCTAssertEqual(EntryWindowChip.custom.label(for: .custom(first: day(2026, 11, 4), last: day(2026, 11, 4)),
                                                    today: nov8), "Nov 4")
        XCTAssertEqual(EntryWindowChip.custom.label(for: .custom(first: day(2025, 12, 30), last: day(2026, 1, 2)),
                                                    today: nov8), "Dec 30, 2025 – Jan 2")
    }

    func testOneChipIsSelected() {
        let custom = EntryWindow.custom(first: day(2026, 11, 2), last: day(2026, 11, 7))
        for (window, chip) in [(EntryWindow.all, EntryWindowChip.all), (.last7, .last7),
                               (.last30, .last30), (custom, .custom)] {
            XCTAssertEqual(EntryWindowChip.allCases.filter { $0.isSelected(by: window) }, [chip])
        }
    }
}

@MainActor
final class CalendarMonthTests: XCTestCase {
    func testNovember2026StartsOnSunday() {
        let weeks = CalendarMonth(year: 2026, month: 11).weeks
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks[0], (1...7).map { day(2026, 11, $0) })
        XCTAssertEqual(weeks[4], [day(2026, 11, 29), day(2026, 11, 30), nil, nil, nil, nil, nil])
    }

    func testFebruary2026IsExactlyFourWeeks() {
        let weeks = CalendarMonth(year: 2026, month: 2).weeks
        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks[0].first, day(2026, 2, 1))
        XCTAssertEqual(weeks[3].last, day(2026, 2, 28))
    }

    func testOctober2026LeadsWithTheMonthBefore() {
        let weeks = CalendarMonth(year: 2026, month: 10).weeks
        // Oct 1 2026 is a Thursday.
        XCTAssertEqual(weeks[0], [nil, nil, nil, nil, day(2026, 10, 1), day(2026, 10, 2), day(2026, 10, 3)])
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count, 31)
    }

    func testMonthsStepAcrossYears() {
        XCTAssertEqual(CalendarMonth(year: 2026, month: 1).previous, CalendarMonth(year: 2025, month: 12))
        XCTAssertEqual(CalendarMonth(year: 2025, month: 12).next, CalendarMonth(year: 2026, month: 1))
    }

    func testMonthTitle() {
        XCTAssertEqual(ChooseDatesSheet.monthTitle(CalendarMonth(year: 2026, month: 11)), "November 2026")
    }
}

final class ChooseDatesModelTests: XCTestCase {
    func testFirstTapPicksTheFirstDay() {
        var model = ChooseDatesModel(today: nov8)
        model.tap(day(2026, 11, 2))
        XCTAssertEqual(model.first, day(2026, 11, 2))
        XCTAssertNil(model.last)
        XCTAssertEqual(model.stretchLabel, "Nov 2")
    }

    func testSecondTapPicksTheLastDay() {
        var model = ChooseDatesModel(today: nov8)
        model.tap(day(2026, 11, 2))
        model.tap(day(2026, 11, 7))
        XCTAssertEqual(model.first, day(2026, 11, 2))
        XCTAssertEqual(model.last, day(2026, 11, 7))
        XCTAssertEqual(model.stretchLabel, "Nov 2 – Nov 7")
    }

    func testAnEarlierSecondTapSwaps() {
        var model = ChooseDatesModel(today: nov8)
        model.tap(day(2026, 11, 7))
        model.tap(day(2026, 11, 2))
        XCTAssertEqual(model.first, day(2026, 11, 2))
        XCTAssertEqual(model.last, day(2026, 11, 7))
    }

    func testAThirdTapStartsOver() {
        var model = ChooseDatesModel(today: nov8)
        model.tap(day(2026, 11, 2))
        model.tap(day(2026, 11, 7))
        model.tap(day(2026, 11, 4))
        XCTAssertEqual(model.first, day(2026, 11, 4))
        XCTAssertNil(model.last)
    }

    func testOneTappedDayIsAOneDayStretch() {
        var model = ChooseDatesModel(today: nov8)
        model.tap(day(2026, 11, 4))
        XCTAssertEqual(model.outcome, .custom(first: day(2026, 11, 4), last: day(2026, 11, 4)))
        XCTAssertEqual(model.state(of: day(2026, 11, 4)), .single)
    }

    func testDaysAfterTodayCannotBePicked() {
        var model = ChooseDatesModel(today: nov8)
        XCTAssertTrue(model.isDisabled(day(2026, 11, 9)))
        XCTAssertFalse(model.isDisabled(nov8))
        model.tap(day(2026, 11, 9))
        XCTAssertNil(model.first)
        XCTAssertEqual(model.state(of: day(2026, 11, 9)), .disabled)
        XCTAssertEqual(model.state(of: nov8), .today)
    }

    func testStretchIsDrawnAsABandWithEnds() {
        let model = ChooseDatesModel(today: nov8, seed: (day(2026, 11, 2), day(2026, 11, 7)))
        XCTAssertEqual(model.state(of: day(2026, 11, 1)), .default)
        XCTAssertEqual(model.state(of: day(2026, 11, 2)), .rangeStart)
        XCTAssertEqual((3...6).map { model.state(of: day(2026, 11, $0)) }, Array(repeating: .inRange, count: 4))
        XCTAssertEqual(model.state(of: day(2026, 11, 7)), .rangeEnd)
    }

    func testNextMonthStopsAtThisMonth() {
        var model = ChooseDatesModel(today: nov8)
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 11))
        XCTAssertFalse(model.canGoForward)
        model.goForward()
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 11))
        XCTAssertTrue(model.canGoBack)
        model.goBack()
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 10))
        XCTAssertTrue(model.canGoForward)
        model.goForward()
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 11))
    }

    func testOpensOnTheCustomStretch() {
        let model = ChooseDatesModel(today: nov8, seed: (day(2026, 9, 28), day(2026, 10, 3)))
        XCTAssertEqual(model.month, CalendarMonth(year: 2026, month: 10))
        XCTAssertEqual(model.outcome, .custom(first: day(2026, 9, 28), last: day(2026, 10, 3)))
    }

    func testDoneAfterClearReturnsToAll() {
        var model = ChooseDatesModel(today: nov8, seed: (day(2026, 11, 2), day(2026, 11, 7)))
        model.clear()
        XCTAssertNil(model.stretchLabel)
        XCTAssertEqual(model.outcome, .all)
    }

    func testDoneWithNothingTappedIsAll() {
        XCTAssertEqual(ChooseDatesModel(today: nov8).outcome, .all)
    }

    /// Cancel discards the sheet's model; the window it was seeded from is untouched.
    func testCancelLeavesTheWindowAsItWas() {
        let window = EntryWindow.custom(first: day(2026, 11, 2), last: day(2026, 11, 7))
        var model = ChooseDatesModel(today: nov8, seed: window.customStretch)
        model.tap(day(2026, 11, 5))
        model.clear()
        XCTAssertEqual(window, .custom(first: day(2026, 11, 2), last: day(2026, 11, 7)))
    }
}
