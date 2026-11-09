#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Eleanor (Central time) on The Riverside
/// Group, her trackers in their canonical hues, and entries by Trevor, Dana and Marcus.
enum TrackersFixtures {
    static let cyan = "#1c8fe0"
    static let teal = "#0d8c86"
    static let violet = "#6f5fe0"

    /// As Trevor sees her: he is an admin of The Riverside Group.
    static let eleanor = TeamReceiver(id: "receiver-eleanor", name: "Eleanor",
                                      timeZone: TimeZone(identifier: "America/Chicago")!, canManage: true)
    /// As Marcus sees her: a caregiver, who logs but doesn't manage trackers.
    static let eleanorForCaregiver = TeamReceiver(id: "receiver-eleanor", name: "Eleanor",
                                                  timeZone: TimeZone(identifier: "America/Chicago")!)

    private static func ago(hours: Double) -> Date { Date().addingTimeInterval(-hours * 3600) }

    static let trackers: [TrackerItem] = [
        TrackerItem(id: "bp", name: "Blood pressure", icon: "heart", color: cyan, status: .active,
                    lastLoggedAt: ago(hours: 2), pausedAt: nil, needsAttention: false),
        TrackerItem(id: "hydration", name: "Hydration", icon: "drop", color: teal, status: .active,
                    lastLoggedAt: ago(hours: 5), pausedAt: nil, needsAttention: false),
        TrackerItem(id: "meals", name: "Meals", icon: "fork.knife", color: cyan, status: .active,
                    lastLoggedAt: ago(hours: 72), pausedAt: nil, needsAttention: true),
        TrackerItem(id: "medication", name: "Medication", icon: "pills", color: violet, status: .active,
                    lastLoggedAt: ago(hours: 9), pausedAt: nil, needsAttention: true),
        TrackerItem(id: "mood", name: "Mood", icon: "face.smiling", color: violet, status: .active,
                    lastLoggedAt: ago(hours: 26), pausedAt: nil, needsAttention: false),
        TrackerItem(id: "walk", name: "Walk", icon: "figure.walk", color: teal, status: .paused,
                    lastLoggedAt: ago(hours: 24 * 9), pausedAt: ago(hours: 24 * 8), needsAttention: false),
        TrackerItem(id: "weight", name: "Weight", icon: "scalemass", color: teal, status: .active,
                    lastLoggedAt: nil, pausedAt: nil, needsAttention: false),
    ]

    static let medicationFields = [
        TrackerFieldInfo(id: "given", label: "Given", kind: .boolean, unit: nil, options: []),
        TrackerFieldInfo(id: "dose", label: "Dose", kind: .choice, unit: nil, options: [
            ChoiceOptionInfo(id: "lis10", label: "Lisinopril 10 mg", retired: false),
            ChoiceOptionInfo(id: "lis5", label: "Lisinopril 5 mg", retired: true),
        ]),
    ]

    static let medication = TrackerProfile(
        id: "medication", name: "Medication", icon: "pills", color: violet, status: .active,
        pausedAt: nil, fields: medicationFields, gapHours: nil, scheduleCount: 2,
        lastLoggedAt: ago(hours: 9), attention: [.unrecorded(occurrenceAt: ago(hours: 4))]
    )

    static let medicationEntries: [TrackerEntry] = [
        TrackerEntry(id: "m1", state: .unrecorded, at: ago(hours: 4), values: [:], note: nil, byName: nil),
        TrackerEntry(id: "m2", state: .logged, at: ago(hours: 9),
                     values: ["given": .bool(true), "dose": .list(["lis10"])], note: nil, byName: "Trevor"),
        TrackerEntry(id: "m3", state: .logged, at: ago(hours: 22),
                     values: ["given": .bool(true), "dose": .list(["lis10"])],
                     note: "Took it with dinner.", byName: "Dana"),
        TrackerEntry(id: "m4", state: .skipped, at: ago(hours: 34), values: [:], note: nil, byName: "Trevor"),
        TrackerEntry(id: "m5", state: .logged, at: ago(hours: 24 * 9),
                     values: ["given": .bool(true), "dose": .list(["lis5"])], note: nil, byName: "Marcus"),
    ]

    static let meals = TrackerProfile(
        id: "meals", name: "Meals", icon: "fork.knife", color: cyan, status: .active, pausedAt: nil,
        fields: [
            TrackerFieldInfo(id: "what", label: "What", kind: .text, unit: nil, options: []),
            TrackerFieldInfo(id: "much", label: "How much", kind: .choice, unit: nil, options: [
                ChoiceOptionInfo(id: "half", label: "Half", retired: false),
                ChoiceOptionInfo(id: "most", label: "Most of it", retired: false),
            ]),
        ],
        gapHours: 24, scheduleCount: 0, lastLoggedAt: ago(hours: 72),
        attention: [.gap(since: ago(hours: 72), gapHours: 24)]
    )

    static let mealsEntries: [TrackerEntry] = [
        TrackerEntry(id: "e1", state: .logged, at: ago(hours: 72),
                     values: ["what": .string("Dinner"), "much": .list(["most"])], note: nil, byName: "Dana"),
        TrackerEntry(id: "e2", state: .logged, at: ago(hours: 78),
                     values: ["what": .string("Lunch"), "much": .list(["half"])], note: nil, byName: "Trevor"),
    ]

    static let bloodPressure = TrackerProfile(
        id: "bp", name: "Blood pressure", icon: "heart", color: cyan, status: .active, pausedAt: nil,
        fields: [
            TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg", options: []),
            TrackerFieldInfo(id: "dia", label: "Diastolic", kind: .number, unit: "mmHg", options: []),
        ],
        gapHours: nil, scheduleCount: 1, lastLoggedAt: ago(hours: 2),
        attention: [.outOfRange(fieldID: "sys", value: 152, range: ValueRangeInfo(low: 90, high: 140))]
    )

    static let bloodPressureEntries: [TrackerEntry] = [
        TrackerEntry(id: "b1", state: .logged, at: ago(hours: 2),
                     values: ["sys": .number(152), "dia": .number(88)], note: nil, byName: "Trevor"),
    ]

    static let weight = TrackerProfile(
        id: "weight", name: "Weight", icon: "scalemass", color: teal, status: .active, pausedAt: nil,
        fields: [TrackerFieldInfo(id: "lb", label: "Weight", kind: .number, unit: "lb", options: [])],
        gapHours: 24 * 7, scheduleCount: 0, lastLoggedAt: nil, attention: []
    )

    static let walk = TrackerProfile(
        id: "walk", name: "Walk", icon: "figure.walk", color: teal, status: .paused,
        pausedAt: ago(hours: 24 * 8),
        fields: [TrackerFieldInfo(id: "min", label: "Minutes", kind: .number, unit: nil, options: [])],
        gapHours: nil, scheduleCount: 0, lastLoggedAt: ago(hours: 24 * 9), attention: []
    )

    static let walkEntries: [TrackerEntry] = [
        TrackerEntry(id: "w1", state: .logged, at: ago(hours: 24 * 9),
                     values: ["min": .number(25)], note: nil, byName: "Marcus"),
        TrackerEntry(id: "w2", state: .logged, at: ago(hours: 24 * 10),
                     values: ["min": .number(20)], note: nil, byName: "Dana"),
    ]

    static let medicationSchedules = [
        TrackerScheduleItem(id: "s1", name: "Morning", days: ScheduleWeekday.allCases, interval: 1,
                            time: "08:00", unrecordedAlert: false),
        TrackerScheduleItem(id: "s2", name: "Evening", days: ScheduleWeekday.allCases, interval: 1,
                            time: "20:00", unrecordedAlert: true),
        TrackerScheduleItem(id: "s3", name: "Lisinopril refill — Mon, every month", days: [.mo], interval: 4,
                            time: "09:30", unrecordedAlert: false),
    ]

    /// The catalog `GET /v1/tracker-templates` serves
    /// (`shared/go-common/v1/domain/templates.json`), in its order.
    static let templates: [TrackerTemplate] = [
        TrackerTemplate(id: "mood", name: "Mood", icon: "face.smiling", color: "#6F5FE0", fields: [
            FieldWrite(label: "Mood", kind: .choice, required: true, multiple: false,
                       options: ["great", "ok", "low", "bad"].map { OptionWrite(label: $0) }),
        ], gapHours: nil),
        TrackerTemplate(id: "shower", name: "Shower", icon: "shower", color: "#38BDF8", fields: [], gapHours: 72),
        TrackerTemplate(id: "urination", name: "Urination", icon: "drop.fill", color: "#EAB308", fields: [
            FieldWrite(label: "Color", kind: .choice, required: false, multiple: false,
                       options: ["clear", "light", "dark"].map { OptionWrite(label: $0) }),
        ], gapHours: nil),
        TrackerTemplate(id: "bowel_movement", name: "Bowel Movement", icon: "toilet", color: "#92400E", fields: [
            FieldWrite(label: "Amount", kind: .choice, required: false, multiple: false,
                       options: ["small", "normal", "large"].map { OptionWrite(label: $0) }),
        ], gapHours: 72),
        TrackerTemplate(id: "medication", name: "Medication", icon: "pills", color: "#30A46C", fields: [],
                        gapHours: nil),
        TrackerTemplate(id: "walk", name: "Walk", icon: "figure.walk", color: "#0EA5E9", fields: [
            FieldWrite(label: "Duration", kind: .number, unit: "min", required: true),
        ], gapHours: nil),
        TrackerTemplate(id: "weight", name: "Weight", icon: "scalemass", color: "#4F8EF7", fields: [
            FieldWrite(label: "Weight", kind: .number, unit: "lb", required: true,
                       range: ValueRangeInfo(low: 80, high: 400)),
        ], gapHours: nil),
        TrackerTemplate(id: "doctor_appointment", name: "Doctor Appointment", icon: "stethoscope",
                        color: "#0891B2", fields: [
            FieldWrite(label: "Doctor", kind: .text, required: true),
            FieldWrite(label: "Specialty", kind: .text, required: false),
            FieldWrite(label: "Location", kind: .text, required: false),
            FieldWrite(label: "Reason", kind: .text, required: false),
            FieldWrite(label: "Outcome", kind: .text, required: false),
            FieldWrite(label: "Follow-up", kind: .datetime, required: false),
        ], gapHours: nil),
    ]

    struct Unreachable: Error {}

    /// The profile a write would leave behind, ids made up, so previews can go on to
    /// Tracker detail.
    static func profile(id: String, from w: TrackerWrite, status: TrackerStatus = .active,
                        scheduleCount: Int = 0) -> TrackerProfile {
        TrackerProfile(
            id: id, name: w.name, icon: w.icon, color: w.color, status: status,
            pausedAt: status == .paused ? Date() : nil,
            fields: w.fields.enumerated().map { i, f in
                TrackerFieldInfo(id: f.fieldID ?? "\(id)-f\(i)", label: f.label, kind: f.kind, unit: f.unit,
                                 required: f.required, paused: f.paused, range: f.range, multiple: f.multiple,
                                 options: f.options.enumerated().map { j, o in
                                     ChoiceOptionInfo(id: o.optionID ?? "\(id)-f\(i)-o\(j)", label: o.label,
                                                      retired: o.retired)
                                 })
            },
            gapHours: w.gapHours, scheduleCount: scheduleCount, lastLoggedAt: nil, attention: []
        )
    }

    static func schedule(id: String, from w: ScheduleWrite) -> TrackerScheduleItem {
        TrackerScheduleItem(id: id, name: w.label ?? "Every week", label: w.label, days: w.days,
                            interval: w.interval, time: w.time, endsOn: w.endsOn,
                            plannedValues: w.plannedValues, unrecordedAlert: w.unrecordedAlert)
    }

    static func service(receivers: [TeamReceiver] = [eleanor],
                        trackers: [TrackerItem] = trackers,
                        failTrackers: Bool = false) -> TrackersService {
        let profiles = [medication, meals, bloodPressure, weight, walk]
        let entries: [String: [TrackerEntry]] = [
            "medication": medicationEntries, "meals": mealsEntries,
            "bp": bloodPressureEntries, "walk": walkEntries,
        ]
        return TrackersService(
            listReceivers: { _ in receivers },
            listTrackers: { _ in
                if failTrackers { throw Unreachable() }
                return trackers
            },
            trackerDetail: { id in
                guard let p = profiles.first(where: { $0.id == id }) else { throw Unreachable() }
                return p
            },
            listEntries: { id, _ in EntriesPage(entries: entries[id] ?? [], nextCursor: nil) },
            listSchedules: { _ in medicationSchedules },
            listTemplates: { templates },
            addTracker: { _, w in profile(id: "new-tracker", from: w) },
            editTracker: { id, w, _ in
                let before = profiles.first(where: { $0.id == id })
                return profile(id: id, from: w, status: before?.status ?? .active,
                               scheduleCount: w.gapHours == nil ? before?.scheduleCount ?? 0 : 0)
            },
            pauseTracker: { id in
                guard let p = profiles.first(where: { $0.id == id }) else { throw Unreachable() }
                return p.with(status: .paused)
            },
            resumeTracker: { id in
                guard let p = profiles.first(where: { $0.id == id }) else { throw Unreachable() }
                return p.with(status: .active)
            },
            addSchedule: { _, w, _ in schedule(id: "new-schedule", from: w) },
            changeSchedule: { id, w in schedule(id: id, from: w) },
            removeSchedule: { _ in }
        )
    }
}
extension TrackerProfile {
    /// This profile paused or resumed, as the pause and resume stubs answer.
    func with(status: TrackerStatus) -> TrackerProfile {
        TrackerProfile(id: id, name: name, icon: icon, color: color, status: status,
                       pausedAt: status == .paused ? Date() : nil, fields: fields, gapHours: gapHours,
                       scheduleCount: scheduleCount, lastLoggedAt: lastLoggedAt,
                       attention: status == .paused ? [] : attention)
    }
}
#endif
