package features_test

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/cucumber/godog"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// homeWorld is what a scenario last saw of Home's reads, and the entry and
// journal note it last seeded, which "that entry" and "that note" mean.
type homeWorld struct {
	lastEntry string
	lastNote  string
	items     []receiverEntryView // needs attention is separate; this is coming up or waiting
	attention []attentionItemView
	timeline  []timelineItemView
	entry     *entryDetailView
	note      *journalNoteView
}

var clockDaysAgo = regexp.MustCompile(`^(\d\d):(\d\d) (\d+) days? ago$`)

// atToday reads the phrases that fall on the receiver's today: a third and
// two thirds of the way from midnight to now, and halfway from now to the
// coming midnight.
func (w *world) atToday(phrase string) (time.Time, bool) {
	now := w.care.now
	local := now.In(zone())
	start := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone())
	end := time.Date(local.Year(), local.Month(), local.Day()+1, 0, 0, 0, 0, zone())
	switch phrase {
	case "early today":
		return start.Add(now.Sub(start) / 3).UTC(), true
	case "earlier today":
		return start.Add(now.Sub(start) * 2 / 3).UTC(), true
	case "later today":
		return now.Add(end.Sub(now) / 2).UTC(), true
	}
	return time.Time{}, false
}

func (w *world) registerHome(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" wrote a journal note about "([^"]*)" at `+when+`: "([^"]*)"$`, w.wroteNote)
	sc.Step(`^"([^"]*)" changed that note `+when+`$`, w.changedNote)
	sc.Step(`^"([^"]*)" changed that entry `+when+`$`, w.changedEntry)

	sc.Step(`^"([^"]*)" looks at what needs attention for "([^"]*)"$`, w.looksAtAttention)
	sc.Step(`^needs attention lists, in this order:$`, w.attentionListsInOrder)
	sc.Step(`^needs attention names `+quoted+` and not "([^"]*)"$`, w.attentionNames)
	sc.Step(`^needs attention says "([^"]*)" on "([^"]*)" read ([\d.]+), outside ([\d.]+) to ([\d.]+)$`, w.attentionSaysOutOfRange)
	sc.Step(`^nothing needs attention on Home$`, w.nothingOnHome)

	sc.Step(`^"([^"]*)" looks at what is coming up for "([^"]*)" on Home$`, w.looksAtComingUpOnHome)
	sc.Step(`^"([^"]*)" opens Coming up for "([^"]*)"$`, w.opensComingUp)
	sc.Step(`^coming up holds, soonest first:$`, w.comingUpHolds)
	sc.Step(`^nothing is coming up$`, w.nothingComingUp)

	sc.Step(`^"([^"]*)" opens the timeline of "([^"]*)" for (today|tomorrow|\d+ days? ago|the day of .+)$`, w.opensTimeline)
	sc.Step(`^the timeline holds, in time order:$`, w.timelineHolds)
	sc.Step(`^the timeline is empty$`, w.timelineIsEmpty)

	sc.Step(`^"([^"]*)" opens Quick log for "([^"]*)"$`, w.opensQuickLog)
	sc.Step(`^the occurrences waiting are, unrecorded first:$`, w.waitingAre)

	sc.Step(`^"([^"]*)" opens that entry$`, w.opensThatEntry)
	sc.Step(`^it is the "([^"]*)" entry (logged|skipped) by "([^"]*)" `+when+`$`, w.entryIsSettledBy)
	sc.Step(`^it is the "([^"]*)" entry still (unrecorded|scheduled), due `+when+`$`, w.entryIsWaiting)
	sc.Step(`^it came from the "([^"]*)" schedule$`, w.entryCameFromSchedule)
	sc.Step(`^it came from no schedule$`, w.entryCameFromNoSchedule)
	sc.Step(`^it marks only "([^"]*)" at ([\d.]+) as outside ([\d.]+) to ([\d.]+)$`, w.entryMarksOnly)
	sc.Step(`^it marks nothing as out of range$`, w.entryMarksNothing)
	sc.Step(`^the entry was last changed by "([^"]*)" `+when+`$`, w.entryLastChangedBy)

	sc.Step(`^"([^"]*)" opens that note$`, w.opensThatNote)
	sc.Step(`^the note reads "([^"]*)", written by "([^"]*)" about `+when+`$`, w.noteReads)
	sc.Step(`^the note was last changed by "([^"]*)" `+when+`$`, w.noteLastChangedBy)
}

// ---- API shapes -------------------------------------------------------------

type badgeView struct {
	TrackerID string `json:"tracker_id"`
	Name      string `json:"name"`
}

type homeEntryView struct {
	EntryID      string         `json:"entry_id"`
	State        string         `json:"state"`
	At           string         `json:"at"`
	Values       map[string]any `json:"values"`
	ByName       string         `json:"by_name"`
	ScheduleName string         `json:"schedule_name"`
}

type attentionItemView struct {
	Tracker    badgeView     `json:"tracker"`
	Attention  attentionView `json:"attention"`
	FieldLabel string        `json:"field_label"`
}

type receiverEntryView struct {
	Tracker badgeView     `json:"tracker"`
	Entry   homeEntryView `json:"entry"`
}

type journalNoteView struct {
	NoteID        string  `json:"note_id"`
	At            string  `json:"at"`
	Body          string  `json:"body"`
	AuthorName    string  `json:"author_name"`
	UpdatedByName string  `json:"updated_by_name"`
	UpdatedAt     *string `json:"updated_at"`
}

type timelineItemView struct {
	Kind    string           `json:"kind"`
	At      string           `json:"at"`
	Tracker *badgeView       `json:"tracker"`
	Entry   *homeEntryView   `json:"entry"`
	Note    *journalNoteView `json:"note"`
}

type dayTimelineView struct {
	Date  string             `json:"date"`
	Items []timelineItemView `json:"items"`
}

type entryDetailView struct {
	Entry         homeEntryView `json:"entry"`
	Tracker       badgeView     `json:"tracker"`
	Fields        []fieldView   `json:"fields"`
	OccurrenceAt  *string       `json:"occurrence_at"`
	SettledAt     *string       `json:"settled_at"`
	UpdatedByName string        `json:"updated_by_name"`
	UpdatedAt     *string       `json:"updated_at"`
	OutOfRange    []struct {
		FieldID string    `json:"field_id"`
		Value   float64   `json:"value"`
		Range   rangeView `json:"range"`
	} `json:"out_of_range"`
}

// ---- seeding notes and changes ------------------------------------------------
//
// Nothing writes journal notes or edits entries through the API until Quick
// log and Edit entry exist, so these go straight to the tables like the
// trackers' history does, tracked for cleanup.

func (w *world) wroteNote(ctx context.Context, by, receiver, phrase, body string) error {
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	p, err := w.signedIn(ctx, by)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	n := domain.JournalNote{
		NoteID: w.nextID("jn"), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, At: at, Body: body,
		Author: p.userID, CreatedAt: at,
	}
	db := w.d.db()
	w.track(journalNoteKey(db.names, n.NoteID))
	w.home.lastNote = n.NoteID
	return db.put(ctx, db.names.JournalNotes, n)
}

// changed records who changed a row last and when, as an edit would.
func (w *world) changed(ctx context.Context, k rowKey, by, phrase string) error {
	p, err := w.signedIn(ctx, by)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.d.db().update(ctx, k, "SET updated_by = :by, updated_at = :at", nil,
		map[string]types.AttributeValue{":by": s(p.userID), ":at": s(at.UTC().Format(store.TimeFormat))})
}

func (w *world) changedNote(ctx context.Context, by, phrase string) error {
	if w.home.lastNote == "" {
		return fmt.Errorf("the scenario has written no journal note")
	}
	return w.changed(ctx, journalNoteKey(w.d.db().names, w.home.lastNote), by, phrase)
}

func (w *world) changedEntry(ctx context.Context, by, phrase string) error {
	if w.home.lastEntry == "" {
		return fmt.Errorf("the scenario has seeded no entry")
	}
	return w.changed(ctx, entryKey(w.d.db().names, w.home.lastEntry), by, phrase)
}

// ---- reading Home -------------------------------------------------------------

// readReceiver GETs one of the receiver's Home reads as label, decoding a 200
// into T.
func readReceiver[T any](ctx context.Context, w *world, label, receiver, what string, q url.Values) (T, error) {
	var zero T
	p, err := w.person(ctx, label)
	if err != nil {
		return zero, err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return zero, err
	}
	path := "/v1/receivers/" + rc.ReceiverID + "/" + what
	if len(q) > 0 {
		path += "?" + q.Encode()
	}
	if err := w.call(ctx, p, http.MethodGet, path, nil); err != nil {
		return zero, err
	}
	if w.last.status != http.StatusOK {
		return zero, nil
	}
	return decodeLast[T](w)
}

// ---- needs attention ----------------------------------------------------------

func (w *world) looksAtAttention(ctx context.Context, label, receiver string) error {
	items, err := readReceiver[[]attentionItemView](ctx, w, label, receiver, "attention", nil)
	w.home.attention = items
	return err
}

func (w *world) attentionLoaded() error {
	if w.last.status != http.StatusOK {
		return w.unexpected("needs attention to load (200)")
	}
	return nil
}

// attentionKind is how a feature names a kind: "unrecorded", "out of range", "gap".
func attentionKind(k string) string { return strings.ReplaceAll(k, " ", "_") }

func (w *world) attentionListsInOrder(t *godog.Table) error {
	if err := w.attentionLoaded(); err != nil {
		return err
	}
	var want, got []string
	for _, row := range table(t) {
		line := row["tracker"] + ": " + attentionKind(row["kind"])
		if row["when"] != "" {
			at, err := w.at(row["when"])
			if err != nil {
				return err
			}
			line += " at " + apiTime(at)
		}
		want = append(want, line)
	}
	rows := table(t)
	for i, a := range w.home.attention {
		line := a.Tracker.Name + ": " + a.Attention.Kind
		if i < len(rows) && rows[i]["when"] != "" {
			var at *string
			switch a.Attention.Kind {
			case "unrecorded":
				at = a.Attention.OccurrenceAt
			case "gap":
				at = a.Attention.Since
			}
			if at != nil {
				line += " at " + *at
			}
		}
		got = append(got, line)
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		return fmt.Errorf("expected needs attention to list, in this order:\n  %s\nbut it listed:\n  %s",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
	return nil
}

func (w *world) attentionNames(list, absent string) error {
	if err := w.attentionLoaded(); err != nil {
		return err
	}
	var got []string
	for _, a := range w.home.attention {
		got = append(got, a.Tracker.Name)
	}
	want := names(list)
	sort.Strings(got)
	sort.Strings(want)
	if fmt.Sprint(got) != fmt.Sprint(want) {
		return w.unexpected(fmt.Sprintf("needs attention to name exactly %q, and not %q", want, absent))
	}
	return nil
}

func (w *world) attentionSaysOutOfRange(field, tracker string, value, low, high float64) error {
	if err := w.attentionLoaded(); err != nil {
		return err
	}
	for _, a := range w.home.attention {
		r := a.Attention.Range
		if a.Tracker.Name == tracker && a.Attention.Kind == "out_of_range" && a.FieldLabel == field &&
			a.Attention.EntryID != "" && a.Attention.Value != nil && *a.Attention.Value == value &&
			r != nil && r.Low != nil && *r.Low == low && r.High != nil && *r.High == high {
			return nil
		}
	}
	return w.unexpected(fmt.Sprintf("needs attention to say %q on %q read %v, outside %v to %v", field, tracker, value, low, high))
}

func (w *world) nothingOnHome() error {
	if err := w.attentionLoaded(); err != nil {
		return err
	}
	if w.home.attention == nil || len(w.home.attention) != 0 {
		return w.unexpected("nothing to need attention (an empty list)")
	}
	return nil
}

// ---- coming up and Quick log's waiting occurrences ------------------------------

func (w *world) readItems(ctx context.Context, label, receiver, what string, q url.Values) error {
	items, err := readReceiver[[]receiverEntryView](ctx, w, label, receiver, what, q)
	w.home.items = items
	return err
}

func (w *world) looksAtComingUpOnHome(ctx context.Context, label, receiver string) error {
	return w.readItems(ctx, label, receiver, "coming-up", url.Values{"limit": {"3"}})
}

func (w *world) opensComingUp(ctx context.Context, label, receiver string) error {
	return w.readItems(ctx, label, receiver, "coming-up", nil)
}

func (w *world) opensQuickLog(ctx context.Context, label, receiver string) error {
	return w.readItems(ctx, label, receiver, "waiting", nil)
}

// itemLines reads a table of | tracker | state | when | schedule | (state and
// schedule optional) and the items last read into comparable lines.
func (w *world) itemLines(t *godog.Table) (want, got []string, err error) {
	rows := table(t)
	withState := false
	for _, c := range t.Rows[0].Cells {
		if c.Value == "state" {
			withState = true
		}
	}
	line := func(tracker, state, at, schedule string) string {
		l := tracker
		if withState {
			l += " " + state
		}
		return l + " at " + at + " from " + strconv.Quote(schedule)
	}
	for _, row := range rows {
		at, err := w.at(row["when"])
		if err != nil {
			return nil, nil, err
		}
		want = append(want, line(row["tracker"], row["state"], apiTime(at), row["schedule"]))
	}
	for _, it := range w.home.items {
		got = append(got, line(it.Tracker.Name, it.Entry.State, it.Entry.At, it.Entry.ScheduleName))
	}
	return want, got, nil
}

func (w *world) comingUpHolds(t *godog.Table) error {
	if w.last.status != http.StatusOK {
		return w.unexpected("coming up to load (200)")
	}
	want, got, err := w.itemLines(t)
	if err != nil {
		return err
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		return fmt.Errorf("expected coming up to hold, soonest first:\n  %s\nbut it held:\n  %s",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
	return nil
}

func (w *world) nothingComingUp() error {
	if w.last.status != http.StatusOK {
		return w.unexpected("coming up to load (200)")
	}
	if w.home.items == nil || len(w.home.items) != 0 {
		return w.unexpected("nothing to be coming up (an empty list)")
	}
	return nil
}

// waitingAre checks the same occurrences are waiting, and that every
// unrecorded one comes before every scheduled one. The PRD orders the two
// groups and nothing within them, so neither does this.
func (w *world) waitingAre(t *godog.Table) error {
	if w.last.status != http.StatusOK {
		return w.unexpected("Quick log's waiting occurrences to load (200)")
	}
	want, got, err := w.itemLines(t)
	if err != nil {
		return err
	}
	sortedWant, sortedGot := append([]string(nil), want...), append([]string(nil), got...)
	sort.Strings(sortedWant)
	sort.Strings(sortedGot)
	fail := func() error {
		return fmt.Errorf("expected the occurrences waiting, unrecorded first, to be:\n  %s\nbut they were:\n  %s",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
	if strings.Join(sortedGot, "\n") != strings.Join(sortedWant, "\n") {
		return fail()
	}
	seenScheduled := false
	for _, it := range w.home.items {
		switch it.Entry.State {
		case "scheduled":
			seenScheduled = true
		case "unrecorded":
			if seenScheduled {
				return fail()
			}
		}
	}
	return nil
}

// ---- the daily timeline -------------------------------------------------------

var daysAgo = regexp.MustCompile(`^(\d+) days? ago$`)

func (w *world) opensTimeline(ctx context.Context, label, receiver, day string) error {
	local := w.care.now.In(zone())
	var date string
	switch {
	case day == "today":
		date = local.Format(time.DateOnly)
	case day == "tomorrow":
		date = local.AddDate(0, 0, 1).Format(time.DateOnly)
	case daysAgo.MatchString(day):
		n, _ := strconv.Atoi(daysAgo.FindStringSubmatch(day)[1])
		date = w.localDay(n)
	default:
		at, err := w.at(strings.TrimPrefix(day, "the day of "))
		if err != nil {
			return err
		}
		date = at.In(zone()).Format(time.DateOnly)
	}
	tl, err := readReceiver[dayTimelineView](ctx, w, label, receiver, "timeline", url.Values{"date": {date}})
	w.home.timeline = tl.Items
	return err
}

// timelineLine is how a feature writes an item: `Medication, logged` or
// `a note: "Rough morning"`.
func timelineLine(it timelineItemView) string {
	switch {
	case it.Kind == "entry" && it.Tracker != nil && it.Entry != nil:
		return fmt.Sprintf("%s at %s: %s, %s by %q", it.Kind, it.At, it.Tracker.Name, it.Entry.State, it.Entry.ByName)
	case it.Kind == "note" && it.Note != nil:
		return fmt.Sprintf("%s at %s: a note: %q by %q", it.Kind, it.At, it.Note.Body, it.Note.AuthorName)
	}
	return fmt.Sprintf("%s at %s: (incomplete item)", it.Kind, it.At)
}

func (w *world) timelineHolds(t *godog.Table) error {
	if w.last.status != http.StatusOK {
		return w.unexpected("the timeline to load (200)")
	}
	var want, got []string
	for _, row := range table(t) {
		at, err := w.at(row["when"])
		if err != nil {
			return err
		}
		kind := "entry"
		if strings.HasPrefix(row["item"], "a note: ") {
			kind = "note"
		}
		want = append(want, fmt.Sprintf("%s at %s: %s by %q", kind, apiTime(at), row["item"], row["by"]))
	}
	for _, it := range w.home.timeline {
		got = append(got, timelineLine(it))
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		return fmt.Errorf("expected the timeline to hold, in time order:\n  %s\nbut it held:\n  %s",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
	return nil
}

func (w *world) timelineIsEmpty() error {
	if w.last.status != http.StatusOK {
		return w.unexpected("the timeline to load (200)")
	}
	if len(w.home.timeline) != 0 {
		var got []string
		for _, it := range w.home.timeline {
			got = append(got, timelineLine(it))
		}
		return fmt.Errorf("expected the timeline to be empty, but it held:\n  %s", strings.Join(got, "\n  "))
	}
	return nil
}

// ---- Entry detail -------------------------------------------------------------

func (w *world) opensThatEntry(ctx context.Context, label string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	if w.home.lastEntry == "" {
		return fmt.Errorf("the scenario has seeded no entry")
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/entries/"+w.home.lastEntry, nil); err != nil {
		return err
	}
	w.home.entry = nil
	if w.last.status == http.StatusOK {
		d, err := decodeLast[entryDetailView](w)
		if err != nil {
			return err
		}
		w.home.entry = &d
	}
	return nil
}

func (w *world) shownEntry() (*entryDetailView, error) {
	if w.home.entry == nil {
		return nil, w.unexpected("Entry detail to load (200)")
	}
	return w.home.entry, nil
}

func (w *world) entryIsSettledBy(tracker, state, by, phrase string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if d.Tracker.Name != tracker || d.Entry.State != state || d.Entry.ByName != by ||
		d.Entry.At != apiTime(at) || d.SettledAt == nil || *d.SettledAt != apiTime(at) {
		return w.unexpected(fmt.Sprintf("the %q entry %s by %q at %s", tracker, state, by, apiTime(at)))
	}
	return nil
}

func (w *world) entryIsWaiting(tracker, state, phrase string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if d.Tracker.Name != tracker || d.Entry.State != state || d.Entry.ByName != "" ||
		d.OccurrenceAt == nil || *d.OccurrenceAt != apiTime(at) || d.SettledAt != nil {
		return w.unexpected(fmt.Sprintf("the %q entry still %s, due %s, by nobody", tracker, state, apiTime(at)))
	}
	return nil
}

func (w *world) entryCameFromSchedule(label string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	if d.Entry.ScheduleName != label {
		return w.unexpected(fmt.Sprintf("the entry to name the %q schedule", label))
	}
	return nil
}

func (w *world) entryCameFromNoSchedule() error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	if d.Entry.ScheduleName != "" {
		return w.unexpected("the entry to name no schedule")
	}
	return nil
}

func (w *world) entryMarksOnly(label string, value, low, high float64) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	labels := map[string]string{}
	for _, f := range d.Fields {
		labels[f.FieldID] = f.Label
	}
	o := d.OutOfRange
	if len(o) != 1 || labels[o[0].FieldID] != label || o[0].Value != value ||
		o[0].Range.Low == nil || *o[0].Range.Low != low || o[0].Range.High == nil || *o[0].Range.High != high {
		return w.unexpected(fmt.Sprintf("the entry to mark only %q at %v as outside %v to %v", label, value, low, high))
	}
	return nil
}

func (w *world) entryMarksNothing() error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	if len(d.OutOfRange) != 0 {
		return w.unexpected("the entry to mark nothing as out of range")
	}
	return nil
}

func (w *world) entryLastChangedBy(by, phrase string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if d.UpdatedByName != by || d.UpdatedAt == nil || *d.UpdatedAt != apiTime(at) {
		return w.unexpected(fmt.Sprintf("the entry to have been last changed by %q at %s", by, apiTime(at)))
	}
	return nil
}

// ---- Journal note -------------------------------------------------------------

func (w *world) opensThatNote(ctx context.Context, label string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	if w.home.lastNote == "" {
		return fmt.Errorf("the scenario has written no journal note")
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/journal-notes/"+w.home.lastNote, nil); err != nil {
		return err
	}
	w.home.note = nil
	if w.last.status == http.StatusOK {
		n, err := decodeLast[journalNoteView](w)
		if err != nil {
			return err
		}
		w.home.note = &n
	}
	return nil
}

func (w *world) shownNote() (*journalNoteView, error) {
	if w.home.note == nil {
		return nil, w.unexpected("the journal note to load (200)")
	}
	return w.home.note, nil
}

func (w *world) noteReads(body, author, phrase string) error {
	n, err := w.shownNote()
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if n.Body != body || n.AuthorName != author || n.At != apiTime(at) {
		return w.unexpected(fmt.Sprintf("the note to read %q, written by %q about %s", body, author, apiTime(at)))
	}
	return nil
}

func (w *world) noteLastChangedBy(by, phrase string) error {
	n, err := w.shownNote()
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if n.UpdatedByName != by || n.UpdatedAt == nil || *n.UpdatedAt != apiTime(at) {
		return w.unexpected(fmt.Sprintf("the note to have been last changed by %q at %s", by, apiTime(at)))
	}
	return nil
}
