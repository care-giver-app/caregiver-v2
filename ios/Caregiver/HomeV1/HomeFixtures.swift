#if DEBUG
import Foundation

/// Preview data bound to `ios/fixtures.md`: Trevor (admin of The Riverside Group,
/// caregiver on Johnson Family), Eleanor in Central time with her canonical trackers and
/// hues, entries by Trevor, Dana and Marcus, and the look-ahead appointments.
///
/// The timeline is yesterday rather than today, so every occurrence on it has come due
/// whatever time a preview runs at.
enum HomeFixtures {
    static let chicago = TimeZone(identifier: "America/Chicago")!
    static let denver = TimeZone(identifier: "America/Denver")!

    // MARK: Teams and receivers

    static let riverside = Account.Team(teamID: "team-riverside", name: "The Riverside Group", role: "admin")
    static let johnson = Account.Team(teamID: "team-johnson", name: "Johnson Family", role: "caregiver")

    /// Trevor on both of his care teams.
    static let trevor = Account(name: "Trevor", email: "twilliams0095@gmail.com", teams: [riverside, johnson])

    static let eleanor = TeamReceiver(id: "receiver-eleanor", name: "Eleanor", timeZone: chicago)
    static let harold = TeamReceiver(id: "receiver-harold", name: "Harold", timeZone: chicago)
    static let rosa = TeamReceiver(id: "receiver-rosa", name: "Rosa", timeZone: chicago)
    static let walter = TeamReceiver(id: "receiver-walter", name: "Walter", timeZone: denver)

    /// What `GET /v1/teams/{id}/receivers` serves for each team, oldest first.
    static let receiversByTeam: [String: [TeamReceiver]] = [
        riverside.teamID: [eleanor, harold, rosa],
        johnson.teamID: [walter],
    ]

    /// The Trackers fixtures, with each team answering with its own receivers.
    static func trackersService(receiversByTeam: [String: [TeamReceiver]] = receiversByTeam,
                                failReceivers: Bool = false) -> TrackersService {
        var service = TrackersFixtures.service()
        service.listReceivers = { teamID in
            if failReceivers { throw TrackersFixtures.Unreachable() }
            return receiversByTeam[teamID] ?? []
        }
        return service
    }

    // MARK: Trackers, as their badges

    static let bloodPressure = TrackerBadgeInfo(id: "bp", name: "Blood pressure", icon: "heart",
                                                color: TrackersFixtures.cyan)
    static let medication = TrackerBadgeInfo(id: "medication", name: "Medication", icon: "pills",
                                             color: TrackersFixtures.violet)
    static let meals = TrackerBadgeInfo(id: "meals", name: "Meals", icon: "fork.knife", color: TrackersFixtures.cyan)
    static let physicalTherapy = TrackerBadgeInfo(id: "physical-therapy", name: "Physical therapy",
                                                  icon: "figure.strengthtraining.functional", color: TrackersFixtures.teal)
    static let cardiology = TrackerBadgeInfo(id: "cardiology", name: "Cardiology check-up", icon: "stethoscope",
                                             color: TrackersFixtures.cyan)
    static let dental = TrackerBadgeInfo(id: "dental", name: "Dental cleaning", icon: "mouth",
                                         color: TrackersFixtures.violet)

    static let bloodPressureFields = [
        TrackerFieldInfo(id: "sys", label: "Systolic", kind: .number, unit: "mmHg",
                         range: ValueRangeInfo(low: 90, high: 140), options: []),
        TrackerFieldInfo(id: "dia", label: "Diastolic", kind: .number, unit: "mmHg",
                         range: ValueRangeInfo(low: 60, high: 90), options: []),
    ]

    // MARK: Times, in Eleanor's zone

    static var today: LocalDay { LocalDay(Date(), zone: chicago) }
    static var yesterday: LocalDay { today.adding(days: -1) }

    static func time(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date {
        day.start(in: chicago).addingTimeInterval(Double(hour * 3600 + minute * 60))
    }

    static func daysAhead(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        time(today.adding(days: days), hour, minute)
    }

    // MARK: Entries

    /// Yesterday's evening dose: due, and nobody wrote it down.
    static var eveningDoseUnrecorded: TrackerEntry {
        TrackerEntry(id: "med-evening-yesterday", state: .unrecorded, at: time(yesterday, 20), values: [:],
                     note: nil, byName: nil, scheduleName: "Evening")
    }

    /// Yesterday's morning dose, given by Dana, from the Morning schedule.
    static var morningDoseLogged: TrackerEntry {
        TrackerEntry(id: "med-morning-yesterday", state: .logged, at: time(yesterday, 8, 5),
                     values: ["given": .bool(true), "dose": .list(["lis10"])], note: nil, byName: "Dana",
                     scheduleName: "Morning")
    }

    /// Yesterday's morning blood pressure check, skipped by Dana.
    static var morningCheckSkipped: TrackerEntry {
        TrackerEntry(id: "bp-morning-yesterday", state: .skipped, at: time(yesterday, 7, 30), values: [:],
                     note: "Cuff battery was dead.", byName: "Dana", scheduleName: "Morning check")
    }

    /// A reading Trevor took ad hoc yesterday evening — systolic over its range.
    static var highReading: TrackerEntry {
        TrackerEntry(id: "bp-high-yesterday", state: .logged, at: time(yesterday, 18, 10),
                     values: ["sys": .number(152), "dia": .number(88)], note: "Seemed tired.", byName: "Trevor")
    }

    /// Tomorrow's morning dose, still ahead.
    static var morningDoseScheduled: TrackerEntry {
        TrackerEntry(id: "med-morning-tomorrow", state: .scheduled, at: daysAhead(1, 8),
                     values: ["dose": .list(["lis10"])], note: nil, byName: nil, scheduleName: "Morning")
    }

    // MARK: Needs attention — one of each kind, in the API's order

    static var attention: [AttentionItem] {
        [
            AttentionItem(tracker: medication,
                          attention: .unrecorded(entryID: eveningDoseUnrecorded.id,
                                                 occurrenceAt: eveningDoseUnrecorded.at)),
            AttentionItem(tracker: bloodPressure,
                          attention: .outOfRange(entryID: highReading.id, fieldID: "sys", fieldLabel: "Systolic",
                                                 unit: "mmHg", value: 152,
                                                 range: ValueRangeInfo(low: 90, high: 140))),
            AttentionItem(tracker: meals,
                          attention: .gap(since: Date().addingTimeInterval(-72 * 3600), gapHours: 24)),
        ]
    }

    // MARK: Coming up — each tracker's next, soonest first

    static var comingUp: [ReceiverEntryItem] {
        [
            ReceiverEntryItem(tracker: medication, entry: morningDoseScheduled),
            ReceiverEntryItem(tracker: physicalTherapy, entry: TrackerEntry(
                id: "pt-tomorrow", state: .scheduled, at: daysAhead(1, 14), values: [:],
                note: "Riverside Clinic", byName: nil)),
            ReceiverEntryItem(tracker: cardiology, entry: TrackerEntry(
                id: "cardiology-9d", state: .scheduled, at: daysAhead(9, 10), values: [:],
                note: "Riverside Clinic", byName: nil)),
            ReceiverEntryItem(tracker: dental, entry: TrackerEntry(
                id: "dental-16d", state: .scheduled, at: daysAhead(16, 9), values: [:],
                note: "Dr. Alvarez", byName: nil)),
        ]
    }

    // MARK: The timeline

    /// Written by Dana, last changed by Trevor.
    static var afternoonNote: JournalNoteInfo {
        JournalNoteInfo(id: "note-yesterday", receiverID: eleanor.id, at: time(yesterday, 15),
                        body: "Quiet afternoon. Ate most of her lunch and napped until four.",
                        authorName: "Dana", createdAt: time(yesterday, 15, 20),
                        updatedByName: "Trevor", updatedAt: time(yesterday, 21, 5))
    }

    /// Yesterday: a skip, a scheduled dose logged, a note, an ad hoc reading, and a dose
    /// nobody recorded — oldest first.
    static var yesterdayTimeline: DayTimeline {
        DayTimeline(day: yesterday, items: [
            .entry(ReceiverEntryItem(tracker: bloodPressure, entry: morningCheckSkipped)),
            .entry(ReceiverEntryItem(tracker: medication, entry: morningDoseLogged)),
            .note(afternoonNote),
            .entry(ReceiverEntryItem(tracker: bloodPressure, entry: highReading)),
            .entry(ReceiverEntryItem(tracker: medication, entry: eveningDoseUnrecorded)),
        ])
    }

    /// A day where nothing was logged and nothing came due.
    static func emptyDay(_ day: LocalDay) -> DayTimeline { DayTimeline(day: day, items: []) }

    // MARK: Entry detail, one per state

    static var scheduledDetail: EntryDetailInfo {
        EntryDetailInfo(entry: morningDoseScheduled, tracker: medication, fields: TrackersFixtures.medicationFields,
                        planned: true, occurrenceAt: morningDoseScheduled.at, unrecordedAlert: false,
                        settledAt: nil, updatedByName: nil, updatedAt: nil, outOfRange: [])
    }

    static var unrecordedDetail: EntryDetailInfo {
        EntryDetailInfo(entry: eveningDoseUnrecorded, tracker: medication, fields: TrackersFixtures.medicationFields,
                        planned: true, occurrenceAt: eveningDoseUnrecorded.at, unrecordedAlert: true,
                        settledAt: nil, updatedByName: nil, updatedAt: nil, outOfRange: [])
    }

    /// Logged from the Morning schedule.
    static var loggedFromScheduleDetail: EntryDetailInfo {
        EntryDetailInfo(entry: morningDoseLogged, tracker: medication, fields: TrackersFixtures.medicationFields,
                        planned: true, occurrenceAt: time(yesterday, 8), unrecordedAlert: false,
                        settledAt: time(yesterday, 8, 12), updatedByName: nil, updatedAt: nil, outOfRange: [])
    }

    /// Logged ad hoc, systolic outside its range, and since corrected by Dana.
    static var loggedOutOfRangeDetail: EntryDetailInfo {
        EntryDetailInfo(entry: highReading, tracker: bloodPressure, fields: bloodPressureFields,
                        planned: false, occurrenceAt: nil, unrecordedAlert: nil,
                        settledAt: time(yesterday, 18, 12), updatedByName: "Dana", updatedAt: time(yesterday, 19),
                        outOfRange: [OutOfRangeInfo(fieldID: "sys", value: 152,
                                                    range: ValueRangeInfo(low: 90, high: 140))])
    }

    static var skippedDetail: EntryDetailInfo {
        EntryDetailInfo(entry: morningCheckSkipped, tracker: bloodPressure, fields: bloodPressureFields,
                        planned: true, occurrenceAt: morningCheckSkipped.at, unrecordedAlert: false,
                        settledAt: time(yesterday, 9, 40), updatedByName: nil, updatedAt: nil, outOfRange: [])
    }

    static var entryDetails: [EntryDetailInfo] {
        [scheduledDetail, unrecordedDetail, loggedFromScheduleDetail, loggedOutOfRangeDetail, skippedDetail]
    }

    // MARK: The service

    struct Unreachable: Error {}

    /// Eleanor's Home: yesterday holds the mixed timeline, every other day is empty. An
    /// entry or note it does not hold answers 404, as one deleted elsewhere would.
    static func service(attention: [AttentionItem]? = nil,
                        comingUp: [ReceiverEntryItem]? = nil,
                        timeline: (@Sendable (LocalDay) -> DayTimeline)? = nil,
                        fail: Bool = false) -> HomeService {
        let attention = attention ?? Self.attention
        let comingUp = comingUp ?? Self.comingUp
        let timeline = timeline ?? { day in day == yesterday ? yesterdayTimeline : emptyDay(day) }
        return HomeService(
            needsAttention: { _, limit in
                if fail { throw Unreachable() }
                return Array(attention.prefix(limit ?? attention.count))
            },
            comingUp: { _, limit in
                if fail { throw Unreachable() }
                return Array(comingUp.prefix(limit ?? comingUp.count))
            },
            dayTimeline: { _, day in
                if fail { throw Unreachable() }
                return timeline(day)
            },
            entry: { id in
                if fail { throw Unreachable() }
                guard let d = entryDetails.first(where: { $0.entry.id == id }) else {
                    throw AppError.forStatus(404, serverMessage: nil)
                }
                return d
            },
            journalNote: { id in
                if fail { throw Unreachable() }
                guard id == afternoonNote.id else { throw AppError.forStatus(404, serverMessage: nil) }
                return afternoonNote
            }
        )
    }
}
#endif
