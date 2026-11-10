import XCTest
import UIKit
@testable import Caregiver

@MainActor
final class FieldEditorTests: XCTestCase {
    private let systolic = FieldDraft(label: "Systolic", kind: .number, unit: "mmHg", required: true,
                                      alertsOutOfRange: true, low: 90, high: 140)

    private var existingDose: FieldDraft { FieldDraft(TrackersFixtures.medicationFields[1]) }

    // MARK: Type

    func testANewFieldCanChangeTypeAndDropsWhatOnlyTheOldTypeHad() {
        let editor = FieldEditor(field: systolic)
        XCTAssertFalse(editor.kindLocked)
        editor.setKind(.text)
        XCTAssertEqual(editor.draft.kind, .text)
        XCTAssertEqual(editor.unit, "")
        XCTAssertFalse(editor.alertsOutOfRange)
        XCTAssertNil(editor.draft.low)
        XCTAssertNil(editor.draft.high)
        XCTAssertEqual(editor.lowText, "")
        XCTAssertEqual(editor.highText, "")
    }

    func testLeavingAChoiceDropsItsOptionsAndAnswers() {
        let editor = FieldEditor(field: FieldDraft(label: "Mood", kind: .choice, multiple: true,
                                                   options: [OptionDraft(label: "great")]))
        editor.setKind(.boolean)
        XCTAssertEqual(editor.options, [])
        XCTAssertFalse(editor.multiple)
    }

    func testAFieldTheTrackerHasKeepsItsTypeAndAnswers() {
        let editor = FieldEditor(field: existingDose)
        XCTAssertTrue(editor.kindLocked)
        editor.setKind(.text)
        XCTAssertEqual(editor.draft.kind, .choice)
        XCTAssertEqual(editor.options.count, 2)
        editor.multiple = true
        XCTAssertFalse(editor.multiple)
    }

    func testANewFieldCanTakeSeveralAnswers() {
        let editor = FieldEditor(field: FieldDraft(label: "Mood", kind: .choice))
        editor.multiple = true
        XCTAssertTrue(editor.multiple)
    }

    // MARK: Options

    func testOptionsCanBeAddedRenamedAndDeletedBeforeTheyAreSaved() {
        let editor = FieldEditor(field: FieldDraft(label: "Mood", kind: .choice))
        let id = editor.addOption()
        XCTAssertEqual(editor.options.map(\.label), [""])
        editor.renameOption(id, to: "Great")
        XCTAssertEqual(editor.options.map(\.label), ["Great"])
        XCTAssertTrue(editor.canDelete(editor.options[0]))
        editor.deleteOption(id)
        XCTAssertEqual(editor.options, [])
    }

    func testAnOptionTheTrackerHasIsRetiredAndBroughtBackNeverDeleted() {
        let editor = FieldEditor(field: existingDose)
        let lis10 = editor.options[0]
        XCTAssertFalse(editor.canDelete(lis10))
        editor.deleteOption(lis10.id)
        XCTAssertEqual(editor.options.count, 2)
        editor.setRetired(lis10.id, true)
        XCTAssertTrue(editor.options[0].retired)
        let lis5 = editor.options[1]
        XCTAssertTrue(lis5.retired)
        editor.setRetired(lis5.id, false)
        XCTAssertFalse(editor.options[1].retired)
        editor.renameOption(lis10.id, to: "Lisinopril 10 mg tablet")
        XCTAssertEqual(editor.field.write.options.first,
                       OptionWrite(optionID: "lis10", label: "Lisinopril 10 mg tablet", retired: true))
    }

    func testAnOptionAddedToAnExistingFieldCanStillBeDeleted() {
        let editor = FieldEditor(field: existingDose)
        let id = editor.addOption()
        editor.setRetired(id, true)
        XCTAssertFalse(editor.options.last!.retired)
        editor.deleteOption(id)
        XCTAssertEqual(editor.options.count, 2)
    }

    func testRetiringEveryOptionStopsSave() {
        let editor = FieldEditor(field: existingDose)
        editor.setRetired(editor.options[0].id, true)
        XCTAssertEqual(editor.problems, ["Add at least one option."])
        XCTAssertFalse(editor.canSave)
    }

    // MARK: Range

    func testTheTypedRangeIsWhatSaves() {
        let editor = FieldEditor(field: systolic)
        XCTAssertEqual(editor.lowText, "90")
        XCTAssertEqual(editor.highText, "140")
        editor.lowText = "85.5"
        editor.highText = ""
        XCTAssertTrue(editor.canSave)
        XCTAssertEqual(editor.field.write.range, ValueRangeInfo(low: 85.5, high: nil))
        XCTAssertEqual(editor.rangeSentence, "A reading below 85.5 mmHg alerts the team.")
    }

    func testTheRangeSentenceNamesEachBoundSet() {
        let editor = FieldEditor(field: systolic)
        XCTAssertEqual(editor.rangeSentence, "A reading below 90 or above 140 mmHg alerts the team.")
        editor.lowText = ""
        XCTAssertEqual(editor.rangeSentence, "A reading above 140 mmHg alerts the team.")
        editor.highText = ""
        XCTAssertNil(editor.rangeSentence)
    }

    func testARangeThatIsNotANumberOrIsEmptyOrBackwardsStopsSave() {
        let editor = FieldEditor(field: systolic)
        editor.lowText = "9o"
        XCTAssertEqual(editor.problems, ["Low and high must be numbers."])
        editor.lowText = ""
        editor.highText = ""
        XCTAssertEqual(editor.problems, ["Set a low, a high, or both."])
        editor.lowText = "150"
        editor.highText = "140"
        XCTAssertEqual(editor.problems, ["The low end can't be above the high end."])
    }

    func testTurningAlertsOffSavesNoRange() {
        let editor = FieldEditor(field: systolic)
        editor.alertsOutOfRange = false
        editor.lowText = "junk"
        XCTAssertTrue(editor.canSave)
        XCTAssertNil(editor.field.write.range)
        XCTAssertNil(editor.field.low)
    }

    func testOnlyANumberAlerts() {
        let editor = FieldEditor(field: FieldDraft(label: "Note", kind: .text))
        editor.alertsOutOfRange = true
        XCTAssertFalse(editor.alertsOutOfRange)
    }

    // MARK: Save

    func testABlankNameStopsSave() {
        let editor = FieldEditor(field: FieldDraft(label: "", kind: .text))
        XCTAssertFalse(editor.canSave)
        editor.label = "Notes"
        XCTAssertTrue(editor.canSave)
    }

    func testSaveKeepsTheFieldsIdentity() {
        let draft = existingDose
        let editor = FieldEditor(field: draft)
        editor.label = "Dose given"
        XCTAssertEqual(editor.field.id, draft.id)
        XCTAssertEqual(editor.field.fieldID, "dose")
    }
}

final class TrackerIconCatalogTests: XCTestCase {
    func testEverySymbolExistsOnTheIPhone() {
        let missing = TrackerIconCatalog.all.map(\.name).filter { UIImage(systemName: $0) == nil }
        XCTAssertEqual(missing, [])
    }

    func testTheCatalogIsAboutTwoHundredIcons() {
        XCTAssertGreaterThanOrEqual(TrackerIconCatalog.all.count, 180)
    }

    func testNoGroupRepeatsAnIcon() {
        for group in TrackerIconCatalog.groups {
            XCTAssertEqual(Set(group.icons.map(\.name)).count, group.icons.count, group.title)
        }
    }

    func testEveryTemplateAndFixtureIconIsInTheCatalog() {
        let icons = TrackersFixtures.templates.map(\.icon) + TrackersFixtures.trackers.map(\.icon)
        for icon in icons {
            XCTAssertTrue(TrackerIconCatalog.contains(icon), icon)
        }
    }

    func testSearchMatchesKeywordsAndNamesByWordPrefix() {
        let names = TrackerIconCatalog.groups(matching: "blood press").flatMap(\.icons).map(\.name)
        XCTAssertTrue(names.contains("heart"))
        XCTAssertTrue(TrackerIconCatalog.groups(matching: "PILL").flatMap(\.icons).map(\.name).contains("pills"))
        XCTAssertTrue(TrackerIconCatalog.groups(matching: "sleep").contains { $0.title == "Activity and rest" })
        XCTAssertEqual(TrackerIconCatalog.groups(matching: "zzzqqq"), [])
        XCTAssertEqual(TrackerIconCatalog.groups(matching: "  "), TrackerIconCatalog.groups)
    }

    func testPaletteRecognizesItsSwatchesInAnyCase() {
        XCTAssertTrue(TrackerColorPalette.isSwatch("#1C8FE0"))
        XCTAssertFalse(TrackerColorPalette.isSwatch("#92400E"))
        XCTAssertEqual(TrackerColorPalette.swatches.count, 9)
    }
}
