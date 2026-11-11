import XCTest
import CaregiverAPI
@testable import Caregiver

private typealias S = Components.Schemas

/// Fixed instants and zones throughout: nothing here reads the clock or the device zone.
private enum Fixed {
    static let chicago = TimeZone(identifier: "America/Chicago")!
    static let denver = TimeZone(identifier: "America/Denver")!

    static func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    static let badge = S.TrackerBadge(trackerId: "bp", name: "Blood pressure", icon: "heart", color: "#1c8fe0")

    static func entry(_ id: String, _ state: S.EntryState, scheduleName: String? = nil,
                      at when: String = "2026-11-08T14:00:00Z") -> S.Entry {
        S.Entry(entryId: id, trackerId: "bp", state: state, at: at(when),
                values: .init(additionalProperties: try! .init(unvalidatedValue: ["sys": 152.0 as (any Sendable)?, "dia": 88 as (any Sendable)?])),
                byName: state == .unrecorded ? nil : "Trevor", scheduleName: scheduleName)
    }

    static let note = S.JournalNote(noteId: "n1", receiverId: "r1", at: at("2026-11-08T21:00:00Z"),
                                    body: "Quiet afternoon.", authorName: "Dana",
                                    createdAt: at("2026-11-08T21:20:00Z"),
                                    updatedByName: "Trevor", updatedAt: at("2026-11-09T03:05:00Z"))
}

// MARK: - Mapping the Home reads

final class HomeServiceMappingTests: XCTestCase {
    func testEachKindOfAttentionKeepsWhatItLeadsTo() {
        let unrecorded = AttentionItem(S.AttentionItem(
            tracker: Fixed.badge,
            attention: .init(kind: .unrecorded, entryId: "e1", occurrenceAt: Fixed.at("2026-11-08T02:00:00Z"))
        ))
        XCTAssertEqual(unrecorded?.attention, .unrecorded(entryID: "e1", occurrenceAt: Fixed.at("2026-11-08T02:00:00Z")))
        XCTAssertEqual(unrecorded?.tracker, TrackerBadgeInfo(id: "bp", name: "Blood pressure", icon: "heart",
                                                             color: "#1c8fe0"))

        let outOfRange = AttentionItem(S.AttentionItem(
            tracker: Fixed.badge,
            attention: .init(kind: .outOfRange, entryId: "e2", fieldId: "sys", value: 152,
                             range: .init(low: 90, high: 140)),
            fieldLabel: "Systolic", unit: "mmHg"
        ))
        XCTAssertEqual(outOfRange?.attention,
                       .outOfRange(entryID: "e2", fieldID: "sys", fieldLabel: "Systolic", unit: "mmHg", value: 152,
                                   range: ValueRangeInfo(low: 90, high: 140)))

        let gap = AttentionItem(S.AttentionItem(
            tracker: Fixed.badge,
            attention: .init(kind: .gap, since: Fixed.at("2026-11-05T18:00:00Z"), gapHours: 24)
        ))
        XCTAssertEqual(gap?.attention, .gap(since: Fixed.at("2026-11-05T18:00:00Z"), gapHours: 24))
    }

    func testAttentionMissingWhatItsKindNeedsIsDropped() {
        XCTAssertNil(AttentionItem(S.AttentionItem(tracker: Fixed.badge, attention: .init(kind: .unrecorded))))
        XCTAssertNil(AttentionItem(S.AttentionItem(tracker: Fixed.badge,
                                                   attention: .init(kind: .outOfRange, fieldId: "sys", value: 1))),
                     "an out-of-range reading with no entry has nowhere to lead")
        XCTAssertNil(AttentionItem(S.AttentionItem(tracker: Fixed.badge, attention: .init(kind: .gap, gapHours: 24))))
    }

    func testTimelineTellsEntriesFromNotesAndKeepsTheirOrder() {
        let timeline = DayTimeline(S.DayTimeline(date: "2026-11-08", items: [
            .init(kind: .entry, at: Fixed.at("2026-11-08T13:30:00Z"), tracker: Fixed.badge,
                  entry: Fixed.entry("skip", .skipped, scheduleName: "Morning check")),
            .init(kind: .note, at: Fixed.note.at, note: Fixed.note),
            .init(kind: .entry, at: Fixed.at("2026-11-09T02:00:00Z"), tracker: Fixed.badge,
                  entry: Fixed.entry("miss", .unrecorded, at: "2026-11-09T02:00:00Z")),
            // Each kind without its part says nothing true, so it is left out.
            .init(kind: .entry, at: Fixed.at("2026-11-09T03:00:00Z"), entry: Fixed.entry("orphan", .logged)),
            .init(kind: .note, at: Fixed.at("2026-11-09T04:00:00Z")),
        ]), asked: LocalDay(year: 2026, month: 11, day: 1))

        XCTAssertEqual(timeline.day, LocalDay(year: 2026, month: 11, day: 8), "the server's date wins")
        XCTAssertEqual(timeline.items.map(\.id), ["entry-skip", "note-n1", "entry-miss"])
        guard case .entry(let skipped) = timeline.items[0] else { return XCTFail("expected an entry") }
        XCTAssertEqual(skipped.entry.state, .skipped)
        XCTAssertEqual(skipped.entry.scheduleName, "Morning check")
        XCTAssertEqual(skipped.tracker.id, "bp")
        guard case .note(let note) = timeline.items[1] else { return XCTFail("expected a note") }
        XCTAssertEqual(note.body, "Quiet afternoon.")
        XCTAssertEqual(timeline.items[2].at, Fixed.at("2026-11-09T02:00:00Z"))
    }

    func testAnEmptyDayIsEmpty() {
        let timeline = DayTimeline(S.DayTimeline(date: "2026-11-07", items: []),
                                   asked: LocalDay(year: 2026, month: 11, day: 7))
        XCTAssertTrue(timeline.items.isEmpty)
    }

    func testEntryDetailKeepsItsOutOfRangeReadingsAndFields() {
        let detail = EntryDetailInfo(S.EntryDetail(
            entry: Fixed.entry("e2", .logged),
            tracker: Fixed.badge,
            fields: [
                .init(fieldId: "sys", label: "Systolic", _type: .number, unit: "mmHg", required: true,
                      status: .active, range: .init(low: 90, high: 140)),
                .init(fieldId: "pulse", label: "Pulse", _type: .number, required: false, status: .paused),
            ],
            planned: false,
            settledAt: Fixed.at("2026-11-08T14:02:00Z"),
            updatedByName: "Dana", updatedAt: Fixed.at("2026-11-08T15:00:00Z"),
            outOfRange: [.init(fieldId: "sys", value: 152, range: .init(low: 90, high: 140))]
        ))
        XCTAssertEqual(detail.entry.state, .logged)
        XCTAssertEqual(detail.entry.values["sys"], .number(152))
        XCTAssertEqual(detail.entry.values["dia"], .number(88))
        XCTAssertEqual(detail.outOfRange, [OutOfRangeInfo(fieldID: "sys", value: 152,
                                                          range: ValueRangeInfo(low: 90, high: 140))])
        XCTAssertEqual(detail.fields.map(\.id), ["sys", "pulse"])
        XCTAssertEqual(detail.fields[0].range, ValueRangeInfo(low: 90, high: 140))
        XCTAssertTrue(detail.fields[1].paused, "a paused field is still there to label old values")
        XCTAssertFalse(detail.planned)
        XCTAssertNil(detail.occurrenceAt)
        XCTAssertEqual(detail.updatedByName, "Dana")
    }

    func testAPlannedEntryNamesItsSchedule() {
        let detail = EntryDetailInfo(S.EntryDetail(
            entry: Fixed.entry("e3", .scheduled, scheduleName: "Morning"), tracker: Fixed.badge, fields: [],
            planned: true, occurrenceAt: Fixed.at("2026-11-09T14:00:00Z"), unrecordedAlert: true, outOfRange: []
        ))
        XCTAssertEqual(detail.entry.scheduleName, "Morning")
        XCTAssertTrue(detail.planned)
        XCTAssertEqual(detail.unrecordedAlert, true)
        XCTAssertNil(detail.settledAt)
    }

    func testJournalNoteSaysWhoChangedItLast() {
        let note = JournalNoteInfo(Fixed.note)
        XCTAssertEqual(note.authorName, "Dana")
        XCTAssertEqual(note.updatedByName, "Trevor")
        XCTAssertEqual(note.updatedAt, Fixed.at("2026-11-09T03:05:00Z"))

        let unchanged = JournalNoteInfo(S.JournalNote(noteId: "n2", receiverId: "r1", at: Fixed.note.at, body: "Hi",
                                                      authorName: "Marcus", createdAt: Fixed.note.createdAt))
        XCTAssertNil(unchanged.updatedByName)
        XCTAssertNil(unchanged.updatedAt)
    }

    func testComingUpCarriesItsTracker() {
        let item = ReceiverEntryItem(S.ReceiverEntry(tracker: Fixed.badge, entry: Fixed.entry("next", .scheduled)))
        XCTAssertEqual(item.id, "next")
        XCTAssertEqual(item.tracker.name, "Blood pressure")
        XCTAssertEqual(item.entry.state, .scheduled)
    }
}

// MARK: - The active care receiver

@MainActor
final class ActiveReceiverModelTests: XCTestCase {
    private let riverside = Account.Team(teamID: "team-riverside", name: "The Riverside Group", role: "admin")
    private let johnson = Account.Team(teamID: "team-johnson", name: "Johnson Family", role: "caregiver")
    private let accountKey = "twilliams0095@gmail.com"

    private let eleanor = TeamReceiver(id: "r-eleanor", name: "Eleanor", timeZone: Fixed.chicago)
    private let harold = TeamReceiver(id: "r-harold", name: "Harold", timeZone: Fixed.chicago)
    private let walter = TeamReceiver(id: "r-walter", name: "Walter", timeZone: Fixed.denver)
    private let anna = TeamReceiver(id: "r-anna", name: "anna", timeZone: Fixed.denver)

    private func account(_ teams: [Account.Team]) -> Account {
        Account(name: "Trevor", email: "TWilliams0095@gmail.com", teams: teams)
    }

    private func model(_ byTeam: [String: [TeamReceiver]], teams: [Account.Team]? = nil,
                       store: LastReceiverStore = .inMemory(),
                       fail: Bool = false, failing: Set<String> = []) -> ActiveReceiverModel {
        let service = TrackersService(
            listReceivers: { id in
                if fail || failing.contains(id) { throw URLError(.timedOut) }
                return byTeam[id] ?? []
            },
            listTrackers: { _ in [] },
            trackerDetail: { _ in throw URLError(.badURL) },
            listEntries: { _, _ in EntriesPage(entries: [], nextCursor: nil) },
            listSchedules: { _ in [] }
        )
        return ActiveReceiverModel(account: account(teams ?? [riverside, johnson]), service: service, store: store)
    }

    func testFirstAlphabeticallyAcrossTeamsWhenNothingIsRemembered() async {
        // Served oldest first: Harold before Eleanor, and Walter on the second team.
        let m = model([riverside.teamID: [harold, eleanor], johnson.teamID: [walter]])
        await m.load()
        XCTAssertEqual(m.active?.receiver.id, eleanor.id)
        XCTAssertEqual(m.active?.team, riverside)
        XCTAssertEqual(m.receivers.map(\.receiver.name), ["Eleanor", "Harold", "Walter"])
    }

    func testTheSortIgnoresCase() async {
        let m = model([riverside.teamID: [eleanor], johnson.teamID: [anna]])
        await m.load()
        XCTAssertEqual(m.active?.receiver.id, anna.id, "\"anna\" comes before \"Eleanor\"")
        XCTAssertEqual(m.active?.team, johnson, "the header names the team the receiver is on")
    }

    func testTheLastRememberedWins() async {
        let store = LastReceiverStore.inMemory([accountKey: walter.id])
        let m = model([riverside.teamID: [eleanor, harold], johnson.teamID: [walter]], store: store)
        await m.load()
        XCTAssertEqual(m.active?.receiver.id, walter.id)
        XCTAssertEqual(m.active?.receiver.canManage, false, "a caregiver on Johnson Family doesn't manage Walter")
    }

    func testARememberedReceiverWhoIsNoLongerListedIsChosenAgain() async {
        // Archived receivers are not listed by the API, so archived and gone look alike.
        let store = LastReceiverStore.inMemory([accountKey: "r-archived"])
        let m = model([riverside.teamID: [harold, eleanor]], store: store)
        await m.load()
        XCTAssertEqual(m.active?.receiver.id, eleanor.id)
        XCTAssertEqual(store.read(accountKey), eleanor.id, "the new choice is what is remembered")
    }

    func testRememberedPerAccount() async {
        let store = LastReceiverStore.inMemory(["someone-else@example.com": harold.id])
        let m = model([riverside.teamID: [harold, eleanor]], store: store)
        await m.load()
        XCTAssertEqual(m.active?.receiver.id, eleanor.id)
    }

    func testChoosingIsRememberedAndShownAtOnce() async {
        let store = LastReceiverStore.inMemory()
        let m = model([riverside.teamID: [eleanor, harold]], store: store)
        await m.load()
        await m.choose(harold.id)
        XCTAssertEqual(m.active?.receiver.id, harold.id)
        XCTAssertEqual(store.read(accountKey), harold.id)

        let again = model([riverside.teamID: [eleanor, harold]], store: store)
        await again.load()
        XCTAssertEqual(again.active?.receiver.id, harold.id)
    }

    func testAnAdminManagesTheChosenReceiver() async {
        let m = model([riverside.teamID: [eleanor]])
        await m.load()
        XCTAssertEqual(m.active?.receiver.canManage, true)
    }

    func testNobodyToCareForDescribesTheFirstTeam() async {
        let m = model([:])
        await m.load()
        XCTAssertEqual(m.phase, .noReceivers(team: riverside, canManage: true))
    }

    func testNobodyToCareForDescribesATeamTheyAdminEvenWhenItIsNotFirst() async {
        let m = model([:], teams: [johnson, riverside])
        await m.load()
        XCTAssertEqual(m.phase, .noReceivers(team: riverside, canManage: true),
                       "Add a care receiver is offered on a team they can add to")
    }

    func testNobodyToCareForAsACaregiver() async {
        let other = Account.Team(teamID: "team-other", name: "Other", role: "caregiver")
        let m = model([:], teams: [johnson, other])
        await m.load()
        XCTAssertEqual(m.phase, .noReceivers(team: johnson, canManage: false))
    }

    func testOneTeamFailingStillChoosesFromTheTeamsThatAnswered() async {
        let m = model([riverside.teamID: [eleanor], johnson.teamID: [anna]], failing: [johnson.teamID])
        await m.load()
        XCTAssertEqual(m.active?.receiver.id, eleanor.id)
        XCTAssertEqual(m.receivers.map(\.receiver.id), [eleanor.id])
    }

    func testNobodyFoundWhileATeamFailedIsAFailureNotNoReceivers() async {
        let m = model([:], failing: [johnson.teamID])
        await m.load()
        guard case .failed = m.phase else { return XCTFail("expected failed, got \(m.phase)") }
    }

    func testAFailedLoadSaysSo() async {
        let m = model([riverside.teamID: [eleanor]], fail: true)
        await m.load()
        guard case .failed = m.phase else { return XCTFail("expected failed, got \(m.phase)") }
    }

    func testTheRuleOnItsOwn() {
        let candidates = [TeamedReceiver(receiver: harold, team: riverside),
                          TeamedReceiver(receiver: eleanor, team: riverside)]
        XCTAssertEqual(ActiveReceiverModel.choose(from: candidates, remembered: nil)?.receiver.id, eleanor.id)
        XCTAssertEqual(ActiveReceiverModel.choose(from: candidates, remembered: harold.id)?.receiver.id, harold.id)
        XCTAssertEqual(ActiveReceiverModel.choose(from: candidates, remembered: "gone")?.receiver.id, eleanor.id)
        XCTAssertNil(ActiveReceiverModel.choose(from: [], remembered: harold.id))
    }
}

// MARK: - Fixtures

final class HomeFixturesTests: XCTestCase {
    func testFixturesCoverWhatHomeDraws() {
        let kinds = HomeFixtures.attention.map { a -> String in
            switch a.attention {
            case .unrecorded: "unrecorded"
            case .outOfRange: "outOfRange"
            case .gap: "gap"
            }
        }
        XCTAssertEqual(kinds, ["unrecorded", "outOfRange", "gap"], "one of each, in the API's order")
        XCTAssertEqual(Set(HomeFixtures.attention.map(\.tracker.id)).count, 3, "never more than one per tracker")

        let states = HomeFixtures.yesterdayTimeline.items.compactMap { item -> EntryState? in
            if case .entry(let e) = item { e.entry.state } else { nil }
        }
        XCTAssertTrue(states.contains(.logged) && states.contains(.skipped) && states.contains(.unrecorded))
        XCTAssertTrue(HomeFixtures.yesterdayTimeline.items.contains { if case .note = $0 { true } else { false } })

        XCTAssertEqual(Set(HomeFixtures.entryDetails.map(\.entry.state)), [.scheduled, .unrecorded, .logged, .skipped])
        XCTAssertFalse(HomeFixtures.loggedOutOfRangeDetail.outOfRange.isEmpty)
        XCTAssertNotNil(HomeFixtures.loggedFromScheduleDetail.entry.scheduleName)
        XCTAssertNotEqual(HomeFixtures.afternoonNote.updatedByName, HomeFixtures.afternoonNote.authorName)
    }
}
