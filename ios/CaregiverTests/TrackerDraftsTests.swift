import XCTest
import CaregiverAPI
@testable import Caregiver

// MARK: - Tracker drafts

final class TrackerDraftTests: XCTestCase {
    private var weightTemplate: TrackerTemplate { TrackersFixtures.templates.first { $0.id == "weight" }! }
    private var moodTemplate: TrackerTemplate { TrackersFixtures.templates.first { $0.id == "mood" }! }

    func testATemplateBecomesANewTrackerWithNoIDs() {
        let draft = TrackerDraft(weightTemplate)
        XCTAssertEqual(draft.name, "Weight")
        XCTAssertEqual(draft.icon, "scalemass")
        XCTAssertEqual(draft.color, "#4F8EF7")
        XCTAssertEqual(draft.problems, [])
        XCTAssertEqual(draft.write, TrackerWrite(name: "Weight", icon: "scalemass", color: "#4F8EF7", fields: [
            FieldWrite(fieldID: nil, label: "Weight", kind: .number, unit: "lb", required: true,
                       range: ValueRangeInfo(low: 80, high: 400)),
        ], gapHours: nil))
    }

    func testAGapTemplateKeepsItsGap() {
        let shower = TrackersFixtures.templates.first { $0.id == "shower" }!
        XCTAssertEqual(TrackerDraft(shower).write.gapHours, 72)
        XCTAssertEqual(TrackerDraft(shower).fields, [])
    }

    func testAChoiceTemplateKeepsItsOptionsInOrder() {
        let write = TrackerDraft(moodTemplate).write
        XCTAssertEqual(write.fields.first?.options.map(\.label), ["great", "ok", "low", "bad"])
        XCTAssertEqual(write.fields.first?.options.compactMap(\.optionID), [])
        XCTAssertEqual(write.fields.first?.multiple, false)
    }

    func testAProfileRoundTripsKeepingEveryIDPausedFieldAndRetiredOption() {
        let profile = TrackerProfile(
            id: "medication", name: "Medication", icon: "pills", color: "#6f5fe0", status: .active,
            pausedAt: nil,
            fields: [
                TrackerFieldInfo(id: "given", label: "Given", kind: .boolean, unit: nil, required: true,
                                 options: []),
                TrackerFieldInfo(id: "dose", label: "Dose", kind: .choice, unit: nil, multiple: true, options: [
                    ChoiceOptionInfo(id: "lis10", label: "Lisinopril 10 mg", retired: false),
                    ChoiceOptionInfo(id: "lis5", label: "Lisinopril 5 mg", retired: true),
                ]),
                TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", paused: true,
                                 range: ValueRangeInfo(low: 90, high: 140), options: []),
            ],
            gapHours: nil, scheduleCount: 2, lastLoggedAt: nil, attention: []
        )
        XCTAssertEqual(TrackerDraft(profile).write, TrackerWrite(name: "Medication", icon: "pills", color: "#6f5fe0", fields: [
            FieldWrite(fieldID: "given", label: "Given", kind: .boolean, required: true),
            FieldWrite(fieldID: "dose", label: "Dose", kind: .choice, required: false, multiple: true, options: [
                OptionWrite(optionID: "lis10", label: "Lisinopril 10 mg"),
                OptionWrite(optionID: "lis5", label: "Lisinopril 5 mg", retired: true),
            ]),
            FieldWrite(fieldID: "sys", label: "Systolic", kind: .number, unit: "mmHg", required: false,
                       paused: true, range: ValueRangeInfo(low: 90, high: 140)),
        ], gapHours: nil))
    }

    func testEditsKeepExistingIDsAndAddNewOnesWithout() {
        var draft = TrackerDraft(TrackersFixtures.medication)
        draft.name = "  Meds  "
        draft.fields[1].options.append(OptionDraft(label: "Lisinopril 20 mg"))
        draft.fields.append(FieldDraft(label: "Note", kind: .text))
        draft.gapHours = 24
        let write = draft.write
        XCTAssertEqual(write.name, "Meds")
        XCTAssertEqual(write.fields.map(\.fieldID), ["given", "dose", nil])
        XCTAssertEqual(write.fields[1].options.map(\.optionID), ["lis10", "lis5", nil])
        XCTAssertEqual(write.gapHours, 24)
    }

    func testTheRangeIsSentOnlyWhileItAlerts() {
        var field = FieldDraft(label: "Weight", kind: .number, unit: "lb", alertsOutOfRange: true, low: 80, high: 400)
        XCTAssertEqual(field.write.range, ValueRangeInfo(low: 80, high: 400))
        field.alertsOutOfRange = false
        XCTAssertNil(field.write.range)
        field.alertsOutOfRange = true
        field.low = nil
        XCTAssertEqual(field.write.range, ValueRangeInfo(low: nil, high: 400), "either end may be open")
        field.high = nil
        XCTAssertNil(field.write.range, "no ends, no range")
    }

    func testUnitRangeMultipleAndOptionsStayWithTheirKinds() {
        var field = FieldDraft(label: "Given", kind: .boolean, unit: "x", alertsOutOfRange: true, low: 1,
                               multiple: true, options: [OptionDraft(label: "a")])
        let write = field.write
        XCTAssertNil(write.unit)
        XCTAssertNil(write.range)
        XCTAssertFalse(write.multiple)
        XCTAssertEqual(write.options, [])
        field.kind = .number
        field.unit = "  "
        XCTAssertNil(field.write.unit, "a blank unit is no unit")
    }

    func testTrackerProblems() {
        var draft = TrackerDraft.scratch(icon: "heart", color: "#1c8fe0")
        XCTAssertEqual(draft.problems, ["Give the tracker a name."])
        draft.name = String(repeating: "a", count: 101)
        XCTAssertEqual(draft.problems, ["Keep the name to 100 characters or fewer."])
        draft.name = "   Hydration "
        draft.color = "1c8fe0"
        draft.icon = ""
        draft.gapHours = 0
        XCTAssertEqual(draft.problems, ["Choose an icon.", "Choose a color.", "A gap must be at least 1 hour."])
        draft.icon = "drop"
        draft.color = "#1C8FE0"
        draft.gapHours = 1
        XCTAssertEqual(draft.problems, [])
    }

    func testFieldProblemsAreNamedOnTheTracker() {
        var draft = TrackerDraft.scratch(icon: "heart", color: "#1c8fe0")
        draft.name = "Meals"
        draft.fields = [FieldDraft(label: "How much", kind: .choice), FieldDraft(label: " ", kind: .text)]
        XCTAssertEqual(draft.problems, ["How much: Add at least one option.", "A field: Give the field a name."])
    }

    func testFieldProblems() {
        XCTAssertEqual(FieldDraft(label: "", kind: .text).problems, ["Give the field a name."])
        XCTAssertEqual(FieldDraft(label: String(repeating: "a", count: 101), kind: .text).problems,
                       ["Keep the field's name to 100 characters or fewer."])
        XCTAssertEqual(FieldDraft(label: "Weight", kind: .number, unit: String(repeating: "u", count: 21)).problems,
                       ["Keep the unit to 20 characters or fewer."])
        XCTAssertEqual(FieldDraft(label: "Weight", kind: .number, alertsOutOfRange: true, low: 200, high: 100).problems,
                       ["The low end can't be above the high end."])
        XCTAssertEqual(FieldDraft(label: "Weight", kind: .number, alertsOutOfRange: false, low: 200, high: 100).problems,
                       [], "a range that doesn't alert isn't sent, so isn't checked")
        XCTAssertEqual(FieldDraft(label: "Dose", kind: .choice,
                                  options: [OptionDraft(optionID: "a", label: "A", retired: true)]).problems,
                       ["Add at least one option."], "retired options don't count")
        XCTAssertEqual(FieldDraft(label: "Dose", kind: .choice, options: [OptionDraft(label: " ")]).problems,
                       ["Give every option a name."], "a blank option still counts as one, so one problem")
        XCTAssertEqual(FieldDraft(label: "Dose", kind: .choice, options: [OptionDraft(label: "A")]).problems, [])
    }

    func testHexColors() {
        XCTAssertTrue(TrackerDraft.isHexColor("#0d8c86"))
        XCTAssertTrue(TrackerDraft.isHexColor("#ABCDEF"))
        XCTAssertFalse(TrackerDraft.isHexColor("#abc"))
        XCTAssertFalse(TrackerDraft.isHexColor("#abcdeg"))
        XCTAssertFalse(TrackerDraft.isHexColor("0d8c86"))
    }
}

// MARK: - Schedule drafts

final class ScheduleDraftTests: XCTestCase {
    private let today = LocalDay(year: 2026, month: 11, day: 9)
    private var fields: [TrackerFieldInfo] { TrackersFixtures.medicationFields + [
        TrackerFieldInfo(id: "mg", label: "Amount", kind: .number, unit: "mg", options: []),
        TrackerFieldInfo(id: "note", label: "Note", kind: .text, unit: nil, options: []),
        TrackerFieldInfo(id: "old", label: "Old", kind: .text, unit: nil, paused: true, options: []),
    ] }

    func testAScheduleRoundTrips() {
        let item = TrackerScheduleItem(
            id: "s1", name: "Morning", label: "Morning", days: [.mo, .we, .fr], interval: 2, time: "08:30",
            startsOn: LocalDay(year: 2026, month: 11, day: 1), endsOn: LocalDay(year: 2026, month: 12, day: 31),
            plannedValues: ["given": .bool(true), "dose": .list(["lis10"])], unrecordedAlert: true
        )
        let draft = ScheduleDraft(item)
        XCTAssertEqual(draft.scheduleID, "s1")
        XCTAssertEqual(draft.problems(today: today), [])
        XCTAssertEqual(draft.write(for: fields), ScheduleWrite(
            label: "Morning", days: [.mo, .we, .fr], interval: 2, time: "08:30",
            endsOn: LocalDay(year: 2026, month: 12, day: 31),
            plannedValues: ["given": .bool(true), "dose": .list(["lis10"])], unrecordedAlert: true
        ))
    }

    func testABlankLabelIsLeftForTheServerToName() {
        var draft = ScheduleDraft(days: [.su, .mo])
        draft.label = "   "
        let write = draft.write(for: fields)
        XCTAssertNil(write.label)
        XCTAssertEqual(write.days, [.mo, .su], "days go out in week order")
    }

    func testPlannedValuesKeepOnlyWhatTheTrackerCanTake() {
        let draft = ScheduleDraft(days: [.mo], plannedValues: [
            "given": .string("yes"),            // wrong kind
            "dose": .list(["lis5", "lis10", "lis10"]), // retired option, duplicate, single answer
            "mg": .number(10),
            "note": .string("  "),               // blank is left for whoever logs it
            "old": .string("paused field"),
            "gone": .number(1),                  // not a field
        ])
        XCTAssertEqual(draft.write(for: fields).plannedValues, ["dose": .list(["lis10"]), "mg": .number(10)])
    }

    func testScheduleProblems() {
        XCTAssertEqual(ScheduleDraft().problems(today: today), ["Choose at least one day."])
        XCTAssertEqual(ScheduleDraft(label: String(repeating: "a", count: 101), days: [.mo], interval: 3,
                                     time: "24:00").problems(today: today),
                       ["Keep the label to 100 characters or fewer.", "Choose how often it repeats.", "Choose a time."])
        XCTAssertEqual(ScheduleDraft(days: [.mo], endsOn: today.adding(days: -1)).problems(today: today),
                       ["The end date can't be before today."])
        XCTAssertEqual(ScheduleDraft(days: [.mo], endsOn: today).problems(today: today), [])
    }

    func testAPastEndDateTheScheduleAlreadyHasMaySaveAgain() {
        let past = LocalDay(year: 2026, month: 10, day: 1)
        var draft = ScheduleDraft(TrackerScheduleItem(id: "s", name: "x", days: [.mo], interval: 1, time: "08:00",
                                                      endsOn: past, unrecordedAlert: false))
        XCTAssertEqual(draft.problems(today: today), [])
        draft.endsOn = LocalDay(year: 2026, month: 10, day: 2)
        XCTAssertEqual(draft.problems(today: today), ["The end date can't be before today."])
    }

    func testTimes() {
        XCTAssertTrue(ScheduleDraft.isTime("00:00"))
        XCTAssertTrue(ScheduleDraft.isTime("23:59"))
        XCTAssertFalse(ScheduleDraft.isTime("8:00"))
        XCTAssertFalse(ScheduleDraft.isTime("12:60"))
    }
}

// MARK: - Wire mapping

final class TrackerWriteMappingTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testEntryValuesEncodeAsPlainJSON() throws {
        let object = try EntryValue.object([
            "n": .number(120.5), "s": .string("Dinner"), "b": .bool(true), "c": .list(["a", "b"]),
        ])
        let decoded = try json(object)
        XCTAssertEqual(decoded["n"] as? Double, 120.5)
        XCTAssertEqual(decoded["s"] as? String, "Dinner")
        XCTAssertEqual(decoded["b"] as? Bool, true)
        XCTAssertEqual(decoded["c"] as? [String], ["a", "b"])
        XCTAssertEqual(EntryValue.map(object), ["n": .number(120.5), "s": .string("Dinner"), "b": .bool(true),
                                                "c": .list(["a", "b"])])
    }

    func testAScheduleWriteGoesOutAsTheContractSaysAndConfirmsOnlyWhenAsked() throws {
        let write = ScheduleWrite(label: nil, days: [.fr, .mo], interval: 4, time: "09:30",
                                  endsOn: LocalDay(year: 2027, month: 1, day: 5),
                                  plannedValues: ["dose": .list(["lis10"])], unrecordedAlert: true)
        let body = try json(try write.newSchedule(replaceGap: false))
        XCTAssertNil(body["label"])
        XCTAssertNil(body["replace_gap"])
        XCTAssertEqual(body["time"] as? String, "09:30")
        XCTAssertEqual(body["ends_on"] as? String, "2027-01-05")
        XCTAssertEqual(body["unrecorded_alert"] as? Bool, true)
        let rule = body["rule"] as? [String: Any]
        XCTAssertEqual(rule?["freq"] as? String, "weekly")
        XCTAssertEqual(rule?["interval"] as? Int, 4)
        XCTAssertEqual(rule?["by_day"] as? [String], ["MO", "FR"])
        XCTAssertEqual((body["planned_values"] as? [String: Any])?["dose"] as? [String], ["lis10"])
        XCTAssertEqual(try json(try write.newSchedule(replaceGap: true))["replace_gap"] as? Bool, true)
        XCTAssertNil(try json(try write.scheduleWrite)["replace_gap"])
    }

    func testTrackerChangesSendStatusesAndConfirmOnlyWhenAsked() throws {
        let write = TrackerDraft(TrackersFixtures.medication).write
        let body = try json(write.trackerChanges(removeSchedules: false))
        XCTAssertNil(body["remove_schedules"])
        let fields = body["fields"] as? [[String: Any]]
        XCTAssertEqual(fields?.map { $0["field_id"] as? String }, ["given", "dose"])
        XCTAssertEqual(fields?.map { $0["status"] as? String }, ["active", "active"])
        let options = fields?[1]["options"] as? [[String: Any]]
        XCTAssertEqual(options?.map { $0["status"] as? String }, ["active", "retired"])
        XCTAssertNil(fields?[0]["options"], "only a choice sends options")
        XCTAssertEqual(try json(write.trackerChanges(removeSchedules: true))["remove_schedules"] as? Bool, true)
    }

    func testAScheduleReadsItsLabelDatesAndPlannedValues() throws {
        let s = Components.Schemas.TrackerSchedule(
            scheduleId: "s1", trackerId: "t", label: nil, name: "Mon, every month",
            rule: .init(freq: .weekly, interval: 4, byDay: [.mo]), time: "09:30", startsOn: "2026-11-02",
            endsOn: nil,
            plannedValues: .init(additionalProperties: try EntryValue.object(["dose": .list(["lis10"])])),
            unrecordedAlert: false
        )
        let item = TrackerScheduleItem(s)
        XCTAssertNil(item.label)
        XCTAssertEqual(item.name, "Mon, every month")
        XCTAssertEqual(item.startsOn, LocalDay(year: 2026, month: 11, day: 2))
        XCTAssertNil(item.endsOn)
        XCTAssertEqual(item.plannedValues, ["dose": .list(["lis10"])])
    }

    func testAFieldReadsRequiredPausedRangeAndMultiple() {
        let profile = TrackerProfile(Components.Schemas.TrackerDetail(
            trackerId: "t", receiverId: "r", teamId: "team", name: "BP", icon: "heart", color: "#1c8fe0",
            status: .active,
            fields: [
                .init(fieldId: "sys", label: "Systolic", _type: .number, unit: "mmHg", required: true,
                      status: .paused, range: .init(low: 90, high: 140)),
                .init(fieldId: "c", label: "Pick", _type: .choice, required: false, status: .active,
                      multiple: true, options: [.init(optionId: "o", label: "O", status: .retired)]),
            ],
            scheduleCount: 0, attention: [], createdAt: Date(timeIntervalSince1970: 0)
        ))
        XCTAssertEqual(profile.fields, [
            TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", required: true, paused: true,
                             range: ValueRangeInfo(low: 90, high: 140), options: []),
            TrackerFieldInfo(id: "c", label: "Pick", kind: .choice, unit: nil, multiple: true,
                             options: [ChoiceOptionInfo(id: "o", label: "O", retired: true)]),
        ])
    }

    func testDayStrings() {
        XCTAssertEqual(LocalDay(dayString: "2026-02-03"), LocalDay(year: 2026, month: 2, day: 3))
        XCTAssertNil(LocalDay(dayString: "2026-2-3"))
        XCTAssertNil(LocalDay(dayString: "nope"))
    }

    func testAnAdminOfTheTeamManagesItsReceivers() {
        let r = TeamReceiver(id: "r", name: "Eleanor", timeZone: .gmt)
        XCTAssertFalse(r.canManage)
        XCTAssertTrue(r.managed(by: Account.Team(teamID: "t", name: "T", role: "admin")).canManage)
        XCTAssertFalse(r.managed(by: Account.Team(teamID: "t", name: "T", role: "caregiver")).canManage)
    }
}
