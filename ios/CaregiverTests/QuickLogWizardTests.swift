import XCTest
import OpenAPIRuntime
import CaregiverAPI
@testable import Caregiver

@MainActor
final class QuickLogWizardTests: XCTestCase {

    private func field(_ key: String, _ type: Components.Schemas.FieldType,
                       unit: String? = nil, options: [String]? = nil) -> Components.Schemas.Field {
        .init(key: key, label: key, _type: type, unit: unit, options: options)
    }

    private func tracker(_ name: String, fields: [Components.Schemas.Field] = [],
                         kind: Components.Schemas.TrackerKind = .event) -> Components.Schemas.Tracker {
        .init(trackerId: "t-\(name)", receiverId: "r1", careGroupId: "g1",
              name: name, kind: kind, fields: fields,
              createdBy: "u1", createdAt: Date(), archived: false)
    }

    // MARK: needingDetails

    func testNeedingDetailsFiltersNoFieldTrackersAndKeepsRosterOrder() {
        let roster = [tracker("Meals"), tracker("Mood", fields: [field("mood", ._enum, options: ["Low", "OK", "Good"])]),
                      tracker("Hydration"), tracker("Pain", fields: [field("pain", .number)])]
        let out = QuickLogWizardModel.needingDetails(roster, selected: Set(roster.map(\.trackerId)))
        XCTAssertEqual(out.map(\.name), ["Mood", "Pain"])
    }

    func testNeedingDetailsIgnoresUnselected() {
        let mood = tracker("Mood", fields: [field("mood", ._enum, options: ["Low"])])
        let out = QuickLogWizardModel.needingDetails([mood, tracker("Meals")], selected: [])
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: helper text

    func testHelperTextCountsTrackersNeedingDetails() {
        XCTAssertEqual(QuickLogWizardModel.helperText(selectedCount: 4, needingDetails: 2),
                       "2 of 4 trackers need details")
    }

    func testHelperTextNilWhenNothingNeedsDetailsOrNothingSelected() {
        XCTAssertNil(QuickLogWizardModel.helperText(selectedCount: 3, needingDetails: 0))
        XCTAssertNil(QuickLogWizardModel.helperText(selectedCount: 0, needingDetails: 0))
    }

    // MARK: primary button title

    func testPrimaryTitleIsNextWhileDetailStepsRemain() {
        XCTAssertEqual(QuickLogWizardModel.primaryTitle(selectedCount: 4, remainingDetailSteps: 2), "Next")
    }

    func testPrimaryTitleIsLogNEventsOnFinalStep() {
        XCTAssertEqual(QuickLogWizardModel.primaryTitle(selectedCount: 4, remainingDetailSteps: 0), "Log 4 events")
        XCTAssertEqual(QuickLogWizardModel.primaryTitle(selectedCount: 1, remainingDetailSteps: 0), "Log 1 event")
    }

    // MARK: retry bookkeeping (decision 5: succeeded posts never repost)

    func testPendingIDsIsAllSelectedBeforeFirstSubmit() {
        XCTAssertEqual(QuickLogWizardModel.pendingIDs(selected: ["a", "b"], results: []), ["a", "b"])
    }

    func testPendingIDsExcludesSuccessesAfterPartialFailure() {
        let results = [QuickLogResult(trackerId: "a", name: "A", success: true, message: nil),
                       QuickLogResult(trackerId: "b", name: "B", success: false, message: "boom")]
        XCTAssertEqual(QuickLogWizardModel.pendingIDs(selected: ["a", "b"], results: results), ["b"])
    }
}
