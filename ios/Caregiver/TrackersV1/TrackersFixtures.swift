#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Eleanor (Central time) on The Riverside
/// Group, her trackers in their canonical hues, and entries by Trevor, Dana and Marcus.
enum TrackersFixtures {
    static let cyan = "#1c8fe0"
    static let teal = "#0d8c86"
    static let violet = "#6f5fe0"

    static let eleanor = TeamReceiver(id: "receiver-eleanor", name: "Eleanor",
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

    struct Unreachable: Error {}

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
            listSchedules: { _ in medicationSchedules }
        )
    }
}
#endif
