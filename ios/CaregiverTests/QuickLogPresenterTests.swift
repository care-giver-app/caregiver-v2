import XCTest
@testable import Caregiver

/// How the tab shell routes Quick log's ways in and out (PRD "Quick log" exits).
final class QuickLogPresenterTests: XCTestCase {
    private let eleanor = TeamReceiver(id: "eleanor", name: "Eleanor",
                                       timeZone: TimeZone(identifier: "America/Chicago")!, canManage: true)
    private let harold = TeamReceiver(id: "harold", name: "Harold",
                                      timeZone: TimeZone(identifier: "America/Chicago")!)

    private let logged = QuickLogModel.Outcome(receiverID: "eleanor", planning: false, latestDay: LocalDay(year: 2026, month: 11, day: 7),
                                               savedAny: true)

    func testEachWayInOpensQuickLogForItsReceiver() {
        var p = QuickLogPresenter()
        p.open(.pick, receiver: eleanor)
        XCTAssertEqual(p.sheet, .quickLog(.pick, eleanor))

        p.open(.tracker(id: "bp"), receiver: harold)
        XCTAssertEqual(p.sheet, .quickLog(.tracker(id: "bp"), harold))
    }

    func testWithNobodyToRecordForTheSheetSaysSo() {
        var p = QuickLogPresenter()
        p.open(.journalNote, receiver: nil)
        XCTAssertEqual(p.sheet, .noReceiver)
    }

    func testAddATrackerSwapsQuickLogForAddTrackerOnTheSameReceiver() {
        var p = QuickLogPresenter()
        p.open(.pick, receiver: eleanor)
        let before = p.sheet?.id
        p.swapToAddTracker(eleanor)
        XCTAssertEqual(p.sheet, .addTracker(eleanor))
        // A new identity, so the one sheet goes and the other takes its place.
        XCTAssertNotEqual(p.sheet?.id, before)
    }

    func testOnlyQuickLogSwapsToAddTracker() {
        var p = QuickLogPresenter()
        p.swapToAddTracker(eleanor)
        XCTAssertNil(p.sheet)
    }

    func testARunThatSavedIsCountedForTheScreensBeneath() {
        var p = QuickLogPresenter()
        p.quickLogEnded(logged)
        XCTAssertEqual(p.runs, QuickLogRuns(count: 1, last: logged))
        let planned = QuickLogModel.Outcome(receiverID: "eleanor", planning: true, latestDay: LocalDay(year: 2026, month: 11, day: 9),
                                            savedAny: true)
        p.quickLogEnded(planned)
        XCTAssertEqual(p.runs, QuickLogRuns(count: 2, last: planned))
    }

    func testCancelOrARunThatSavedNothingChangesNothingBeneath() {
        var p = QuickLogPresenter()
        p.quickLogEnded(nil)
        p.quickLogEnded(QuickLogModel.Outcome(receiverID: "eleanor", planning: false, latestDay: nil, savedAny: false))
        XCTAssertEqual(p.runs, QuickLogRuns())
    }

    func testATrackerMadeInQuickLogsPlaceIsPushedOnce() {
        var p = QuickLogPresenter()
        p.open(.pick, receiver: eleanor)
        p.swapToAddTracker(eleanor)
        XCTAssertNil(p.takeCreated(), "Quick log going is not Add tracker making one")
        p.trackerCreated("new-tracker", receiver: eleanor)
        XCTAssertEqual(p.takeCreated(), QuickLogPresenter.Created(trackerID: "new-tracker", receiver: eleanor))
        XCTAssertNil(p.takeCreated())
    }
}

final class EntryFieldInputsTests: XCTestCase {
    private func field(_ id: String, _ kind: FieldKind, paused: Bool = false) -> TrackerFieldInfo {
        TrackerFieldInfo(id: id, label: id, kind: kind, unit: nil, paused: paused, options: [])
    }

    func testTwoNumbersInARowShareOneAndPausedFieldsAreLeftOut() {
        let rows = EntryFieldInputs.rows([
            field("sys", .number), field("dia", .number), field("pulse", .number),
            field("old", .text, paused: true), field("note", .text), field("a", .number), field("b", .number),
        ])
        XCTAssertEqual(rows.map { $0.map(\.id) }, [["sys", "dia"], ["pulse"], ["note"], ["a", "b"]])
    }
}
