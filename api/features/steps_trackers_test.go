package features_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/cucumber/godog"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// receiverZone is every seeded receiver's time zone. Dates sent to the API
// (narrowing the entries) are days in it.
const receiverZone = "America/Chicago"

// careWorld is a scenario's care receivers, trackers and what the API last
// showed of them.
type careWorld struct {
	now       time.Time                  // the scenario's "now", to the second, that every "ago" counts back from
	receivers map[string]domain.Receiver // receiver name as written → its row
	trackers  map[string]*domain.Tracker // tracker name as written → its row as seeded or created
	signedIn  map[string]bool            // people whose user row exists, so their name shows on what they logged
	list      []trackerRowView           // the Trackers list last read
	detail    *trackerDetailView         // the Tracker detail last answered
	entries   []entryView                // every entry the last read of a tracker's entries returned
	pages     int                        // how many pages that read took
	templates []map[string]any           // the template catalogue last read
}

func newCareWorld() careWorld {
	return careWorld{
		now:       time.Now().UTC().Truncate(time.Second),
		receivers: map[string]domain.Receiver{}, trackers: map[string]*domain.Tracker{}, signedIn: map[string]bool{},
	}
}

// when is a time phrase a feature writes: "3 hours ago", "1 day from now",
// "noon 2 days ago" (noon in the receiver's zone).
const when = `(\d+ (?:minutes?|hours?|days?) (?:ago|from now)|noon \d+ days? ago)`

// quoted is a list of quoted names: "A", "B" and "C".
const quoted = `((?:"[^"]*"(?:, | and )?)+)`

func (w *world) registerTrackers(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" looks after "([^"]*)"$`, w.looksAfter)
	sc.Step(`^"([^"]*)" has a tracker "([^"]*)"$`, w.hasTracker)
	sc.Step(`^"([^"]*)" has a number field "([^"]*)" expected between ([\d.]+) and ([\d.]+)$`, w.hasRangedNumberField)
	sc.Step(`^"([^"]*)" has a number field "([^"]*)"$`, w.hasNumberField)
	sc.Step(`^"([^"]*)" has a choice field "([^"]*)" offering `+quoted+`$`, w.hasChoiceField)
	sc.Step(`^"([^"]*)" is watched by a gap of (\d+) hours$`, w.isWatchedByGap)
	sc.Step(`^"([^"]*)" was created `+when+`$`, w.wasCreated)
	sc.Step(`^"([^"]*)" was paused `+when+`$`, w.wasPaused)
	sc.Step(`^the "([^"]*)" field of "([^"]*)" has been paused$`, w.fieldHasBeenPaused)
	sc.Step(`^"([^"]*)" has a schedule labelled "([^"]*)" (every day|on [A-Za-z, ]+) at (\d\d:\d\d)$`, w.hasLabelledSchedule)
	sc.Step(`^"([^"]*)" has an unlabelled schedule (every day|on [A-Za-z, ]+) at (\d\d:\d\d)$`, w.hasUnlabelledSchedule)

	sc.Step(`^"([^"]*)" logged "([^"]*)" `+when+`$`, w.loggedAt)
	sc.Step(`^"([^"]*)" logged "([^"]*)" `+when+` with "([^"]*)" at ([\d.]+)$`, w.loggedWithValue)
	sc.Step(`^"([^"]*)" logged "([^"]*)" at noon on each of the last (\d+) days$`, w.loggedDaily)
	sc.Step(`^"([^"]*)" was due `+when+` and nobody has logged it$`, w.wasDueUnlogged)
	sc.Step(`^"([^"]*)" is scheduled for `+when+`$`, w.isScheduledFor)
	sc.Step(`^"([^"]*)" has these entries:$`, w.hasTheseEntries)

	sc.Step(`^"([^"]*)" opens the trackers of "([^"]*)"$`, w.opensTrackers)
	sc.Step(`^the trackers listed are `+quoted+`$`, w.trackersListedAre)
	sc.Step(`^the list holds no trackers$`, w.listHoldsNoTrackers)
	sc.Step(`^the row for "([^"]*)" says it has never been logged$`, w.rowNeverLogged)
	sc.Step(`^the row for "([^"]*)" says it was last logged `+when+`$`, w.rowLastLogged)
	sc.Step(`^the row for "([^"]*)" says it was paused `+when+`$`, w.rowPaused)
	sc.Step(`^the row for "([^"]*)" (says|does not say) it needs attention$`, w.rowNeedsAttention)

	sc.Step(`^"([^"]*)" opens "([^"]*)"$`, w.opensTracker)
	sc.Step(`^it is called "([^"]*)"$`, w.itIsCalled)
	sc.Step(`^it reads as (paused|active)$`, w.itReadsAs)
	sc.Step(`^it has never been logged$`, w.itHasNeverBeenLogged)
	sc.Step(`^it has (\d+) schedules?$`, w.itHasSchedules)
	sc.Step(`^it is not watched by a gap$`, w.itIsNotWatchedByGap)
	sc.Step(`^it is watched by a gap of (\d+) hours$`, w.itIsWatchedByGap)
	sc.Step(`^it collects `+quoted+`$`, w.itCollects)
	sc.Step(`^it collects nothing$`, w.itCollectsNothing)
	sc.Step(`^it collects "([^"]*)" as a number in "([^"]*)" expected between ([\d.]+) and ([\d.]+)$`, w.itCollectsRangedNumber)
	sc.Step(`^its "([^"]*)" field is (paused|active)$`, w.itsFieldIs)
	sc.Step(`^its "([^"]*)" field is still a number$`, w.itsFieldIsStillNumber)
	sc.Step(`^its "([^"]*)" field still offers "([^"]*)"$`, w.itsFieldStillOffers)
	sc.Step(`^nothing about it needs attention$`, w.nothingNeedsAttention)
	sc.Step(`^it needs attention because "([^"]*)" read ([\d.]+), outside ([\d.]+) to ([\d.]+)$`, w.needsAttentionOutOfRange)
	sc.Step(`^it needs attention for the care due `+when+` that went unrecorded$`, w.needsAttentionUnrecorded)
	sc.Step(`^it needs attention because nothing has been logged since it was created `+when+`, past its gap of (\d+) hours$`, w.needsAttentionGapSinceCreated)
	sc.Step(`^it needs attention because nothing has been logged since `+when+`, past its gap of (\d+) hours$`, w.needsAttentionGapSinceLogged)

	sc.Step(`^"([^"]*)" reads the entries of "([^"]*)"$`, w.readsEntries)
	sc.Step(`^"([^"]*)" reads the entries of "([^"]*)" (\d+) at a time$`, w.readsEntriesPaged)
	sc.Step(`^"([^"]*)" narrows the entries of "([^"]*)" to the days from (\d+) days ago to (\d+) days ago$`, w.narrowsEntries)
	sc.Step(`^the entries are, newest first:$`, w.entriesAre)
	sc.Step(`^they came in (\d+) pages$`, w.cameInPages)

	sc.Step(`^"([^"]*)" looks at the tracker templates$`, w.looksAtTemplates)
	sc.Step(`^the templates are `+quoted+`, in that order$`, w.templatesAre)
	sc.Step(`^the templates watched by a gap are `+quoted+`$`, w.templatesWatchedByGap)
	sc.Step(`^the "([^"]*)" template collects nothing$`, w.templateCollectsNothing)
	sc.Step(`^"([^"]*)" adds a tracker to "([^"]*)" from the "([^"]*)" template$`, w.addsFromTemplate)
	sc.Step(`^"([^"]*)" adds a tracker to "([^"]*)" from the "([^"]*)" template without its "([^"]*)" field$`, w.addsFromTemplateWithout)

	sc.Step(`^"([^"]*)" saves "([^"]*)" without its "([^"]*)" field$`, w.savesWithoutField)
	sc.Step(`^"([^"]*)" saves "([^"]*)" without the "([^"]*)" option of its "([^"]*)" field$`, w.savesWithoutOption)
	sc.Step(`^"([^"]*)" saves "([^"]*)" with its "([^"]*)" field turned into a text field$`, w.savesWithTypeChanged)
	sc.Step(`^"([^"]*)" (pauses|resumes) the "([^"]*)" field of "([^"]*)"$`, w.pausesField)
	sc.Step(`^"([^"]*)" turns on a gap of (\d+) hours for "([^"]*)"$`, w.turnsOnGap)
	sc.Step(`^the answer is (\d+) saying "([^"]*)"$`, w.answerIsSaying)

	sc.Step(`^"([^"]*)" (pauses|resumes) "([^"]*)"$`, w.pausesTracker)
	sc.Step(`^nothing is still waiting ahead of "([^"]*)"$`, w.nothingWaitingAhead)

	sc.Step(`^"([^"]*)" reads the schedules of "([^"]*)"$`, w.readsSchedules)
	sc.Step(`^the schedules are named "([^"]*)" and one named for its days and time rather than "([^"]*)"$`, w.schedulesNamed)
}

// ---- API shapes -------------------------------------------------------------

type rangeView struct {
	Low  *float64 `json:"low"`
	High *float64 `json:"high"`
}

type trackerRowView struct {
	TrackerID      string  `json:"tracker_id"`
	Name           string  `json:"name"`
	Status         string  `json:"status"`
	LastLoggedAt   *string `json:"last_logged_at"`
	PausedAt       *string `json:"paused_at"`
	NeedsAttention bool    `json:"needs_attention"`
}

type optionView struct {
	OptionID string `json:"option_id"`
	Label    string `json:"label"`
	Status   string `json:"status"`
}

type fieldView struct {
	FieldID  string       `json:"field_id"`
	Label    string       `json:"label"`
	Type     string       `json:"type"`
	Unit     string       `json:"unit,omitempty"`
	Required bool         `json:"required"`
	Status   string       `json:"status"`
	Range    *rangeView   `json:"range,omitempty"`
	Multiple *bool        `json:"multiple,omitempty"`
	Options  []optionView `json:"options,omitempty"`
}

type attentionView struct {
	Kind         string     `json:"kind"`
	EntryID      string     `json:"entry_id"`
	OccurrenceAt *string    `json:"occurrence_at"`
	FieldID      string     `json:"field_id"`
	Value        *float64   `json:"value"`
	Range        *rangeView `json:"range"`
	Since        *string    `json:"since"`
	GapHours     *int       `json:"gap_hours"`
}

type trackerDetailView struct {
	TrackerID     string          `json:"tracker_id"`
	Name          string          `json:"name"`
	Icon          string          `json:"icon"`
	Color         string          `json:"color"`
	Status        string          `json:"status"`
	PausedAt      *string         `json:"paused_at"`
	Fields        []fieldView     `json:"fields"`
	GapHours      *int            `json:"gap_hours"`
	ScheduleCount int             `json:"schedule_count"`
	LastLoggedAt  *string         `json:"last_logged_at"`
	Attention     []attentionView `json:"attention"`
}

type entryView struct {
	EntryID string         `json:"entry_id"`
	State   string         `json:"state"`
	At      string         `json:"at"`
	Values  map[string]any `json:"values"`
	ByName  string         `json:"by_name"`
}

type entryPageView struct {
	Entries    []entryView `json:"entries"`
	NextCursor string      `json:"next_cursor"`
}

type scheduleView struct {
	ScheduleID string `json:"schedule_id"`
	Label      string `json:"label"`
	Name       string `json:"name"`
}

// apiTime is how the API writes a time.
func apiTime(t time.Time) string { return t.UTC().Format(time.RFC3339) }

// ---- times and names ----------------------------------------------------------

var (
	relativeTime = regexp.MustCompile(`^(\d+) (minute|hour|day)s? (ago|from now)$`)
	noonDaysAgo  = regexp.MustCompile(`^noon (\d+) days? ago$`)
	quotedName   = regexp.MustCompile(`"([^"]*)"`)
)

func zone() *time.Location {
	loc, err := time.LoadLocation(receiverZone)
	if err != nil {
		panic(err)
	}
	return loc
}

// at turns a feature's time phrase into a time, counted back from the
// scenario's now.
func (w *world) at(phrase string) (time.Time, error) {
	if m := noonDaysAgo.FindStringSubmatch(phrase); m != nil {
		n, _ := strconv.Atoi(m[1])
		local := w.care.now.In(zone()).AddDate(0, 0, -n)
		return time.Date(local.Year(), local.Month(), local.Day(), 12, 0, 0, 0, zone()).UTC(), nil
	}
	m := relativeTime.FindStringSubmatch(phrase)
	if m == nil {
		return time.Time{}, fmt.Errorf("cannot read the time %q", phrase)
	}
	n, _ := strconv.Atoi(m[1])
	unit := map[string]time.Duration{"minute": time.Minute, "hour": time.Hour, "day": 24 * time.Hour}[m[2]]
	d := time.Duration(n) * unit
	if m[3] == "ago" {
		d = -d
	}
	return w.care.now.Add(d), nil
}

// localDay is the date n days ago in the receiver's zone.
func (w *world) localDay(n int) string {
	return w.care.now.In(zone()).AddDate(0, 0, -n).Format(time.DateOnly)
}

func names(list string) []string {
	var out []string
	for _, m := range quotedName.FindAllStringSubmatch(list, -1) {
		out = append(out, m[1])
	}
	return out
}

// slug is the id a seeded field or option gets from its label.
func slug(label string) string { return strings.ToLower(strings.ReplaceAll(label, " ", "-")) }

func (w *world) nextID(kind string) string {
	w.n++
	return fmt.Sprintf("features-%s-%s%d", w.suffix, kind, w.n)
}

// ---- seeding receivers, trackers and schedules ---------------------------------
//
// Nothing a caregiver does makes a receiver yet (that is the Team area), and a
// tracker's history cannot be written through the API before the logging
// endpoints exist, so these rows go straight to the tables, tracked for cleanup.

func (w *world) looksAfter(ctx context.Context, team, receiver string) error {
	teamID, err := w.teamID(team)
	if err != nil {
		return err
	}
	rc := domain.Receiver{
		ReceiverID: w.nextID("rc"), TeamID: teamID, Name: receiver + " " + w.suffix, TimeZone: receiverZone,
		Status: domain.ReceiverActive, CreatedBy: "features", CreatedAt: w.care.now.Add(-60 * 24 * time.Hour),
	}
	db := w.d.db()
	w.track(receiverKey(db.names, rc.ReceiverID))
	if err := db.put(ctx, db.names.Receivers, rc); err != nil {
		return fmt.Errorf("could not write the receiver: %w", err)
	}
	w.care.receivers[receiver] = rc
	return nil
}

func (w *world) receiver(name string) (domain.Receiver, error) {
	rc, ok := w.care.receivers[name]
	if !ok {
		return domain.Receiver{}, fmt.Errorf("the scenario never said who %q is", name)
	}
	return rc, nil
}

func (w *world) tracker(name string) (*domain.Tracker, error) {
	t, ok := w.care.trackers[name]
	if !ok {
		return nil, fmt.Errorf("the scenario never made a tracker called %q", name)
	}
	return t, nil
}

func (w *world) putTracker(ctx context.Context, t *domain.Tracker) error {
	db := w.d.db()
	if err := db.put(ctx, db.names.Trackers, t); err != nil {
		return fmt.Errorf("could not write the tracker %q: %w", t.Name, err)
	}
	return nil
}

// hasTracker seeds an active tracker with no fields and no gap, made a month ago.
func (w *world) hasTracker(ctx context.Context, receiver, name string) error {
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	t := &domain.Tracker{
		TrackerID: w.nextID("tr"), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, Name: name, Icon: "star",
		Color: "#4F8EF7", Fields: []domain.Field{}, Status: domain.TrackerActive, CreatedBy: "features",
		CreatedAt: w.care.now.Add(-30 * 24 * time.Hour),
	}
	w.track(trackerKey(w.d.db().names, t.TrackerID))
	w.care.trackers[name] = t
	return w.putTracker(ctx, t)
}

func (w *world) addField(ctx context.Context, tracker string, f domain.Field) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	f.FieldID, f.Status = slug(f.Label), domain.FieldActive
	t.Fields = append(t.Fields, f)
	return w.putTracker(ctx, t)
}

func (w *world) hasRangedNumberField(ctx context.Context, tracker, label string, low, high float64) error {
	return w.addField(ctx, tracker, domain.Field{Label: label, Type: domain.FieldNumber, Required: true, Range: &domain.Range{Low: &low, High: &high}})
}

func (w *world) hasNumberField(ctx context.Context, tracker, label string) error {
	return w.addField(ctx, tracker, domain.Field{Label: label, Type: domain.FieldNumber, Required: false})
}

func (w *world) hasChoiceField(ctx context.Context, tracker, label, options string) error {
	f := domain.Field{Label: label, Type: domain.FieldChoice, Required: true}
	for _, o := range names(options) {
		f.Options = append(f.Options, domain.ChoiceOption{OptionID: slug(o), Label: o, Status: domain.OptionActive})
	}
	return w.addField(ctx, tracker, f)
}

func (w *world) isWatchedByGap(ctx context.Context, tracker string, hours int) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	t.GapHours = &hours
	return w.putTracker(ctx, t)
}

func (w *world) wasCreated(ctx context.Context, tracker, phrase string) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	if t.CreatedAt, err = w.at(phrase); err != nil {
		return err
	}
	return w.putTracker(ctx, t)
}

func (w *world) wasPaused(ctx context.Context, tracker, phrase string) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	t.Status, t.PausedAt, t.PausedBy = domain.TrackerPaused, &at, "features"
	return w.putTracker(ctx, t)
}

func (w *world) fieldHasBeenPaused(ctx context.Context, label, tracker string) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	for i := range t.Fields {
		if t.Fields[i].Label == label {
			at := w.care.now.Add(-24 * time.Hour)
			t.Fields[i].Status, t.Fields[i].PausedAt = domain.FieldPaused, &at
			return w.putTracker(ctx, t)
		}
	}
	return fmt.Errorf("%q has no field %q", tracker, label)
}

var weekdayCodes = map[string]string{"Mon": "MO", "Tue": "TU", "Wed": "WE", "Thu": "TH", "Fri": "FR", "Sat": "SA", "Sun": "SU"}

func (w *world) seedSchedule(ctx context.Context, tracker, label, days, hhmm string) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	var byDay []string
	if days == "every day" {
		byDay = []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}
	} else {
		for _, d := range strings.FieldsFunc(strings.TrimPrefix(days, "on "), func(r rune) bool { return r == ',' || r == ' ' }) {
			if d == "and" {
				continue
			}
			code, ok := weekdayCodes[d]
			if !ok {
				return fmt.Errorf("unknown weekday %q", d)
			}
			byDay = append(byDay, code)
		}
	}
	// Schedules list oldest first; each one seeded is made a minute after the last.
	id := w.nextID("sc")
	sc := domain.Schedule{
		ScheduleID: id, TrackerID: t.TrackerID, ReceiverID: t.ReceiverID, TeamID: t.TeamID, Label: label,
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: byDay}, Time: hhmm, StartsOn: w.localDay(7),
		PlannedValues: map[string]any{}, CreatedBy: "features", CreatedAt: w.care.now.Add(-time.Duration(1000-w.n) * time.Minute),
	}
	db := w.d.db()
	w.track(scheduleKey(db.names, sc.ScheduleID))
	return db.put(ctx, db.names.Schedules, sc)
}

func (w *world) hasLabelledSchedule(ctx context.Context, tracker, label, days, hhmm string) error {
	return w.seedSchedule(ctx, tracker, label, days, hhmm)
}

func (w *world) hasUnlabelledSchedule(ctx context.Context, tracker, days, hhmm string) error {
	return w.seedSchedule(ctx, tracker, "", days, hhmm)
}

// ---- seeding entries ----------------------------------------------------------

// signedIn makes sure the person has used the app once, so their account (and
// with it the name on what they logged) exists.
func (w *world) signedIn(ctx context.Context, label string) (*person, error) {
	p, err := w.person(ctx, label)
	if err != nil {
		return nil, err
	}
	if !w.care.signedIn[label] {
		if _, err := w.account(ctx, label); err != nil {
			return nil, err
		}
		w.care.signedIn[label] = true
	}
	return p, nil
}

// seedEntry writes one entry in the state a caregiver would see it in:
// "logged", "skipped", "unrecorded" (scheduled, its time passed), or
// "scheduled" (still to come). values are keyed by field label.
func (w *world) seedEntry(ctx context.Context, tracker, state string, at time.Time, by string, values map[string]float64) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	e := domain.Entry{
		EntryID: w.nextID("en"), TrackerID: t.TrackerID, ReceiverID: t.ReceiverID, TeamID: t.TeamID,
		Values: map[string]any{}, CreatedBy: "features", CreatedAt: at, TimelineAt: at,
	}
	for label, v := range values {
		e.Values[slug(label)] = v
	}
	var who string
	if by != "" {
		p, err := w.signedIn(ctx, by)
		if err != nil {
			return err
		}
		who = p.userID
	}
	switch state {
	case "logged":
		e.State, e.OccurredAt, e.LoggedAt, e.LoggedBy, e.CreatedBy = domain.EntryLogged, &at, &at, who, who
	case "skipped":
		e.State, e.OccurrenceAt, e.SkippedAt, e.SkippedBy = domain.EntrySkipped, &at, &at, who
	case "unrecorded", "scheduled":
		e.State, e.OccurrenceAt, e.OpenAt = domain.EntryScheduled, &at, &at
	default:
		return fmt.Errorf("unknown entry state %q", state)
	}
	db := w.d.db()
	w.track(entryKey(db.names, e.EntryID))
	return db.put(ctx, db.names.Entries, e)
}

func (w *world) loggedAt(ctx context.Context, by, tracker, phrase string) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.seedEntry(ctx, tracker, "logged", at, by, nil)
}

func (w *world) loggedWithValue(ctx context.Context, by, tracker, phrase, field string, v float64) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.seedEntry(ctx, tracker, "logged", at, by, map[string]float64{field: v})
}

func (w *world) loggedDaily(ctx context.Context, by, tracker string, days int) error {
	for n := 1; n <= days; n++ {
		at, _ := w.at(fmt.Sprintf("noon %d days ago", n))
		if err := w.seedEntry(ctx, tracker, "logged", at, by, nil); err != nil {
			return err
		}
	}
	return nil
}

func (w *world) wasDueUnlogged(ctx context.Context, tracker, phrase string) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.seedEntry(ctx, tracker, "unrecorded", at, "", nil)
}

func (w *world) isScheduledFor(ctx context.Context, tracker, phrase string) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.seedEntry(ctx, tracker, "scheduled", at, "", nil)
}

// parseValues reads "Systolic 160, Pulse 72".
func parseValues(s string) (map[string]float64, error) {
	out := map[string]float64{}
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		i := strings.LastIndex(part, " ")
		if i < 0 {
			return nil, fmt.Errorf("cannot read the value %q", part)
		}
		v, err := strconv.ParseFloat(part[i+1:], 64)
		if err != nil {
			return nil, fmt.Errorf("cannot read the value %q", part)
		}
		out[part[:i]] = v
	}
	return out, nil
}

// table reads a data table into one map per row, keyed by its header.
func table(t *godog.Table) []map[string]string {
	var rows []map[string]string
	for i, r := range t.Rows {
		if i == 0 {
			continue
		}
		row := map[string]string{}
		for j, c := range r.Cells {
			row[t.Rows[0].Cells[j].Value] = strings.TrimSpace(c.Value)
		}
		rows = append(rows, row)
	}
	return rows
}

func (w *world) hasTheseEntries(ctx context.Context, tracker string, t *godog.Table) error {
	for _, row := range table(t) {
		at, err := w.at(row["when"])
		if err != nil {
			return err
		}
		values, err := parseValues(row["values"])
		if err != nil {
			return err
		}
		if err := w.seedEntry(ctx, tracker, row["state"], at, row["by"], values); err != nil {
			return err
		}
	}
	return nil
}

// ---- the Trackers list --------------------------------------------------------

func (w *world) opensTrackers(ctx context.Context, label, receiver string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/receivers/"+rc.ReceiverID+"/trackers", nil); err != nil {
		return err
	}
	w.care.list = nil
	if w.last.status == http.StatusOK {
		rows, err := decodeLast[[]trackerRowView](w)
		if err != nil {
			return err
		}
		w.care.list = rows
	}
	return nil
}

func (w *world) row(name string) (trackerRowView, error) {
	for _, r := range w.care.list {
		if r.Name == name {
			return r, nil
		}
	}
	return trackerRowView{}, w.unexpected(fmt.Sprintf("the Trackers list to hold %q", name))
}

func (w *world) trackersListedAre(list string) error {
	var got []string
	for _, r := range w.care.list {
		got = append(got, r.Name)
	}
	want := names(list)
	if fmt.Sprint(got) != fmt.Sprint(want) {
		return w.unexpected(fmt.Sprintf("the trackers listed to be %q", want))
	}
	return nil
}

func (w *world) listHoldsNoTrackers() error {
	if w.last.status != http.StatusOK || len(w.care.list) != 0 {
		return w.unexpected("the Trackers list to hold no trackers")
	}
	return nil
}

func (w *world) rowNeverLogged(name string) error {
	r, err := w.row(name)
	if err != nil {
		return err
	}
	if r.LastLoggedAt != nil {
		return w.unexpected(fmt.Sprintf("the row for %q to say it has never been logged", name))
	}
	return nil
}

func (w *world) rowLastLogged(name, phrase string) error {
	r, err := w.row(name)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if r.LastLoggedAt == nil || *r.LastLoggedAt != apiTime(at) {
		return w.unexpected(fmt.Sprintf("the row for %q to say it was last logged at %s", name, apiTime(at)))
	}
	return nil
}

func (w *world) rowPaused(name, phrase string) error {
	r, err := w.row(name)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if r.Status != "paused" || r.PausedAt == nil || *r.PausedAt != apiTime(at) {
		return w.unexpected(fmt.Sprintf("the row for %q to say it was paused at %s", name, apiTime(at)))
	}
	return nil
}

func (w *world) rowNeedsAttention(name, says string) error {
	r, err := w.row(name)
	if err != nil {
		return err
	}
	if r.NeedsAttention != (says == "says") {
		return w.unexpected(fmt.Sprintf("the row for %q to %s it needs attention", name, strings.TrimSuffix(says, "s")))
	}
	return nil
}

// ---- Tracker detail -----------------------------------------------------------

// keepDetail remembers the answer as the tracker last shown, when it is one.
func (w *world) keepDetail() error {
	w.care.detail = nil
	if w.last.status != http.StatusOK && w.last.status != http.StatusCreated {
		return nil
	}
	d, err := decodeLast[trackerDetailView](w)
	if err != nil {
		return err
	}
	w.care.detail = &d
	return nil
}

func (w *world) opensTracker(ctx context.Context, label, tracker string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/trackers/"+t.TrackerID, nil); err != nil {
		return err
	}
	return w.keepDetail()
}

func (w *world) shown() (*trackerDetailView, error) {
	if w.care.detail == nil {
		return nil, w.unexpected("a tracker to be shown")
	}
	return w.care.detail, nil
}

func (w *world) field(label string) (fieldView, error) {
	d, err := w.shown()
	if err != nil {
		return fieldView{}, err
	}
	for _, f := range d.Fields {
		if f.Label == label {
			return f, nil
		}
	}
	return fieldView{}, w.unexpected(fmt.Sprintf("%q to collect a field %q", d.Name, label))
}

func (w *world) itIsCalled(name string) error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if d.Name != name {
		return w.unexpected(fmt.Sprintf("the tracker to be called %q", name))
	}
	return nil
}

func (w *world) itReadsAs(status string) error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if d.Status != status || (status == "paused") != (d.PausedAt != nil) {
		return w.unexpected(fmt.Sprintf("%q to read as %s", d.Name, status))
	}
	return nil
}

func (w *world) itHasNeverBeenLogged() error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if d.LastLoggedAt != nil {
		return w.unexpected(fmt.Sprintf("%q never to have been logged", d.Name))
	}
	return nil
}

func (w *world) itHasSchedules(n int) error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if d.ScheduleCount != n {
		return w.unexpected(fmt.Sprintf("%q to have %d schedules", d.Name, n))
	}
	return nil
}

func (w *world) itIsNotWatchedByGap() error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if d.GapHours != nil {
		return w.unexpected(fmt.Sprintf("%q not to be watched by a gap", d.Name))
	}
	return nil
}

func (w *world) itIsWatchedByGap(hours int) error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if d.GapHours == nil || *d.GapHours != hours {
		return w.unexpected(fmt.Sprintf("%q to be watched by a gap of %d hours", d.Name, hours))
	}
	return nil
}

func (w *world) itCollects(list string) error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	var got []string
	for _, f := range d.Fields {
		got = append(got, f.Label)
	}
	if want := names(list); fmt.Sprint(got) != fmt.Sprint(want) {
		return w.unexpected(fmt.Sprintf("%q to collect %q", d.Name, want))
	}
	return nil
}

func (w *world) itCollectsNothing() error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if len(d.Fields) != 0 {
		return w.unexpected(fmt.Sprintf("%q to collect nothing", d.Name))
	}
	return nil
}

func (w *world) itCollectsRangedNumber(label, unit string, low, high float64) error {
	f, err := w.field(label)
	if err != nil {
		return err
	}
	if f.Type != "number" || f.Unit != unit || f.Range == nil || f.Range.Low == nil || *f.Range.Low != low ||
		f.Range.High == nil || *f.Range.High != high {
		return w.unexpected(fmt.Sprintf("%q to be a number in %q expected between %v and %v", label, unit, low, high))
	}
	return nil
}

func (w *world) itsFieldIs(label, status string) error {
	f, err := w.field(label)
	if err != nil {
		return err
	}
	if f.Status != status {
		return w.unexpected(fmt.Sprintf("the %q field to be %s", label, status))
	}
	return nil
}

func (w *world) itsFieldIsStillNumber(label string) error {
	f, err := w.field(label)
	if err != nil {
		return err
	}
	if f.Type != "number" {
		return w.unexpected(fmt.Sprintf("the %q field still to be a number", label))
	}
	return nil
}

func (w *world) itsFieldStillOffers(label, option string) error {
	f, err := w.field(label)
	if err != nil {
		return err
	}
	for _, o := range f.Options {
		if o.Label == option {
			return nil
		}
	}
	return w.unexpected(fmt.Sprintf("the %q field still to offer %q", label, option))
}

func (w *world) nothingNeedsAttention() error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	if len(d.Attention) != 0 {
		return w.unexpected(fmt.Sprintf("nothing about %q to need attention", d.Name))
	}
	return nil
}

func (w *world) attention(kind, want string, match func(attentionView) bool) error {
	d, err := w.shown()
	if err != nil {
		return err
	}
	for _, a := range d.Attention {
		if a.Kind == kind && match(a) {
			return nil
		}
	}
	return w.unexpected(fmt.Sprintf("%q to need attention %s", d.Name, want))
}

func (w *world) needsAttentionOutOfRange(label string, value, low, high float64) error {
	f, err := w.field(label)
	if err != nil {
		return err
	}
	return w.attention("out_of_range", fmt.Sprintf("because %q read %v, outside %v to %v", label, value, low, high), func(a attentionView) bool {
		return a.FieldID == f.FieldID && a.EntryID != "" && a.Value != nil && *a.Value == value &&
			a.Range != nil && a.Range.Low != nil && *a.Range.Low == low && a.Range.High != nil && *a.Range.High == high
	})
}

func (w *world) needsAttentionUnrecorded(phrase string) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.attention("unrecorded", "for the care due at "+apiTime(at), func(a attentionView) bool {
		return a.EntryID != "" && a.OccurrenceAt != nil && *a.OccurrenceAt == apiTime(at)
	})
}

func (w *world) needsAttentionGap(phrase string, hours int) error {
	since, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.attention("gap", fmt.Sprintf("for nothing logged since %s, past a gap of %d hours", apiTime(since), hours), func(a attentionView) bool {
		return a.Since != nil && *a.Since == apiTime(since) && a.GapHours != nil && *a.GapHours == hours
	})
}

func (w *world) needsAttentionGapSinceCreated(phrase string, hours int) error {
	return w.needsAttentionGap(phrase, hours)
}

func (w *world) needsAttentionGapSinceLogged(phrase string, hours int) error {
	return w.needsAttentionGap(phrase, hours)
}

// ---- a tracker's entries --------------------------------------------------------

// readEntries reads every page of the tracker's entries with the given query,
// keeping all of them and how many pages it took.
func (w *world) readEntries(ctx context.Context, label, tracker string, q url.Values) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	w.care.entries, w.care.pages = nil, 0
	for {
		if w.care.pages > 50 {
			return fmt.Errorf("the entries of %q never reached an end", tracker)
		}
		path := "/v1/trackers/" + t.TrackerID + "/entries"
		if len(q) > 0 {
			path += "?" + q.Encode()
		}
		if err := w.call(ctx, p, http.MethodGet, path, nil); err != nil {
			return err
		}
		if w.last.status != http.StatusOK {
			return nil
		}
		page, err := decodeLast[entryPageView](w)
		if err != nil {
			return err
		}
		w.care.pages++
		w.care.entries = append(w.care.entries, page.Entries...)
		if page.NextCursor == "" {
			return nil
		}
		q.Set("cursor", page.NextCursor)
	}
}

func (w *world) readsEntries(ctx context.Context, label, tracker string) error {
	return w.readEntries(ctx, label, tracker, url.Values{})
}

func (w *world) readsEntriesPaged(ctx context.Context, label, tracker string, n int) error {
	return w.readEntries(ctx, label, tracker, url.Values{"limit": {strconv.Itoa(n)}})
}

func (w *world) narrowsEntries(ctx context.Context, label, tracker string, from, to int) error {
	return w.readEntries(ctx, label, tracker, url.Values{"from": {w.localDay(from)}, "to": {w.localDay(to)}})
}

func (w *world) entriesAre(t *godog.Table) error {
	if w.last.status != http.StatusOK {
		return w.unexpected("the entries to load (200)")
	}
	var want, got []string
	for _, row := range table(t) {
		at, err := w.at(row["when"])
		if err != nil {
			return err
		}
		vals := strings.Split(row["values"], ",")
		for i := range vals {
			vals[i] = strings.TrimSpace(vals[i])
		}
		sort.Strings(vals)
		want = append(want, fmt.Sprintf("%s at %s by %q values %s", row["state"], apiTime(at), row["by"], strings.Join(vals, ", ")))
	}
	tr := map[string]string{} // field_id → label, across every seeded tracker
	for _, t := range w.care.trackers {
		for _, f := range t.Fields {
			tr[f.FieldID] = f.Label
		}
	}
	for _, e := range w.care.entries {
		var vals []string
		for id, v := range e.Values {
			vals = append(vals, fmt.Sprintf("%s %v", tr[id], v))
		}
		sort.Strings(vals)
		got = append(got, fmt.Sprintf("%s at %s by %q values %s", e.State, e.At, e.ByName, strings.Join(vals, ", ")))
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		return fmt.Errorf("expected the entries, newest first:\n  %s\nbut they were:\n  %s",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
	return nil
}

func (w *world) cameInPages(n int) error {
	if w.care.pages != n {
		return fmt.Errorf("expected the entries to come in %d pages, but they came in %d", n, w.care.pages)
	}
	return nil
}

// ---- Add tracker ----------------------------------------------------------------

func (w *world) readTemplates(ctx context.Context, p *person) error {
	if err := w.call(ctx, p, http.MethodGet, "/v1/tracker-templates", nil); err != nil {
		return err
	}
	w.care.templates = nil
	if w.last.status != http.StatusOK {
		return w.unexpected("the tracker templates to load (200)")
	}
	tps, err := decodeLast[[]map[string]any](w)
	if err != nil {
		return err
	}
	w.care.templates = tps
	return nil
}

func (w *world) looksAtTemplates(ctx context.Context, label string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	return w.readTemplates(ctx, p)
}

func (w *world) template(name string) (map[string]any, error) {
	for _, tp := range w.care.templates {
		if tp["name"] == name {
			return tp, nil
		}
	}
	return nil, fmt.Errorf("the catalogue has no template called %q", name)
}

func (w *world) templatesAre(list string) error {
	var got []string
	for _, tp := range w.care.templates {
		got = append(got, fmt.Sprint(tp["name"]))
	}
	if want := names(list); fmt.Sprint(got) != fmt.Sprint(want) {
		return fmt.Errorf("expected the templates %q, in that order, but they were %q", want, got)
	}
	return nil
}

func (w *world) templatesWatchedByGap(list string) error {
	var got []string
	for _, tp := range w.care.templates {
		if tp["gap_hours"] != nil {
			got = append(got, fmt.Sprint(tp["name"]))
		}
	}
	if want := names(list); fmt.Sprint(got) != fmt.Sprint(want) {
		return fmt.Errorf("expected the templates watched by a gap to be %q, but they were %q", want, got)
	}
	return nil
}

func (w *world) templateCollectsNothing(name string) error {
	tp, err := w.template(name)
	if err != nil {
		return err
	}
	if fs, _ := tp["fields"].([]any); len(fs) != 0 {
		return fmt.Errorf("expected the %q template to collect nothing, but it has %d fields", name, len(fs))
	}
	return nil
}

// addFromTemplate sends Add tracker's Create with the template's own shape,
// less any field the admin dropped from it first.
func (w *world) addFromTemplate(ctx context.Context, label, receiver, name, drop string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	if err := w.readTemplates(ctx, p); err != nil {
		return err
	}
	tp, err := w.template(name)
	if err != nil {
		return err
	}
	fields := []any{}
	for _, f := range tp["fields"].([]any) {
		if f.(map[string]any)["label"] != drop {
			fields = append(fields, f)
		}
	}
	body := map[string]any{"name": tp["name"], "icon": tp["icon"], "color": tp["color"], "fields": fields}
	if g, ok := tp["gap_hours"]; ok {
		body["gap_hours"] = g
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/receivers/"+rc.ReceiverID+"/trackers", body); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		d, err := decodeLast[trackerDetailView](w)
		if err != nil {
			return err
		}
		w.track(trackerKey(w.d.db().names, d.TrackerID))
		w.care.trackers[name] = &domain.Tracker{TrackerID: d.TrackerID, ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, Name: d.Name}
	}
	return w.keepDetail()
}

func (w *world) addsFromTemplate(ctx context.Context, label, receiver, name string) error {
	return w.addFromTemplate(ctx, label, receiver, name, "")
}

func (w *world) addsFromTemplateWithout(ctx context.Context, label, receiver, name, field string) error {
	return w.addFromTemplate(ctx, label, receiver, name, field)
}

// ---- Edit tracker ---------------------------------------------------------------

// edit sends Edit tracker's Save: the tracker as it stands, with change applied.
func (w *world) edit(ctx context.Context, label, tracker string, change func(body map[string]any, fields []map[string]any) ([]map[string]any, error)) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/trackers/"+t.TrackerID, nil); err != nil {
		return err
	}
	if w.last.status != http.StatusOK {
		return w.unexpected(fmt.Sprintf("%q to open %q before editing it (200)", label, tracker))
	}
	d, err := decodeLast[trackerDetailView](w)
	if err != nil {
		return err
	}
	var fields []map[string]any
	for _, f := range d.Fields {
		b, _ := json.Marshal(f)
		var m map[string]any
		_ = json.Unmarshal(b, &m)
		fields = append(fields, m)
	}
	body := map[string]any{"name": d.Name, "icon": d.Icon, "color": d.Color, "gap_hours": d.GapHours}
	if fields, err = change(body, fields); err != nil {
		return err
	}
	if fields == nil {
		fields = []map[string]any{}
	}
	body["fields"] = fields
	if err := w.call(ctx, p, http.MethodPut, "/v1/trackers/"+t.TrackerID, body); err != nil {
		return err
	}
	return w.keepDetail()
}

func withField(fields []map[string]any, label string, f func(map[string]any)) ([]map[string]any, error) {
	for _, fl := range fields {
		if fl["label"] == label {
			f(fl)
			return fields, nil
		}
	}
	return nil, fmt.Errorf("the tracker has no field %q", label)
}

func (w *world) savesWithoutField(ctx context.Context, label, tracker, field string) error {
	return w.edit(ctx, label, tracker, func(_ map[string]any, fields []map[string]any) ([]map[string]any, error) {
		var kept []map[string]any
		for _, f := range fields {
			if f["label"] != field {
				kept = append(kept, f)
			}
		}
		if len(kept) == len(fields) {
			return nil, fmt.Errorf("%q has no field %q", tracker, field)
		}
		return kept, nil
	})
}

func (w *world) savesWithoutOption(ctx context.Context, label, tracker, option, field string) error {
	return w.edit(ctx, label, tracker, func(_ map[string]any, fields []map[string]any) ([]map[string]any, error) {
		return withField(fields, field, func(f map[string]any) {
			var kept []any
			for _, o := range f["options"].([]any) {
				if o.(map[string]any)["label"] != option {
					kept = append(kept, o)
				}
			}
			f["options"] = kept
		})
	})
}

func (w *world) savesWithTypeChanged(ctx context.Context, label, tracker, field string) error {
	return w.edit(ctx, label, tracker, func(_ map[string]any, fields []map[string]any) ([]map[string]any, error) {
		return withField(fields, field, func(f map[string]any) {
			f["type"] = "text"
			delete(f, "unit")
			delete(f, "range")
		})
	})
}

func (w *world) pausesField(ctx context.Context, label, verb, field, tracker string) error {
	status := "paused"
	if verb == "resumes" {
		status = "active"
	}
	return w.edit(ctx, label, tracker, func(_ map[string]any, fields []map[string]any) ([]map[string]any, error) {
		return withField(fields, field, func(f map[string]any) { f["status"] = status })
	})
}

func (w *world) turnsOnGap(ctx context.Context, label string, hours int, tracker string) error {
	return w.edit(ctx, label, tracker, func(body map[string]any, fields []map[string]any) ([]map[string]any, error) {
		body["gap_hours"] = hours
		return fields, nil
	})
}

func (w *world) answerIsSaying(status int, part string) error {
	want := fmt.Sprintf("the answer to be %d saying %q", status, part)
	if w.last.status != status {
		return w.unexpected(want)
	}
	var body struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(w.last.body, &body) != nil || !strings.Contains(body.Message, part) {
		return w.unexpected(want)
	}
	return nil
}

// ---- pausing and resuming -------------------------------------------------------

func (w *world) pausesTracker(ctx context.Context, label, verb, tracker string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	action := "pause"
	if verb == "resumes" {
		action = "resume"
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/trackers/"+t.TrackerID+"/"+action, nil); err != nil {
		return err
	}
	return w.keepDetail()
}

// nothingWaitingAhead reads the tracker's occurrences still to come straight
// from the table: they are what Coming up will show, and its endpoint is not
// built yet.
func (w *world) nothingWaitingAhead(ctx context.Context, tracker string) error {
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	ahead, _, err := w.d.db().stores().Entries.ListByTrackerTimeline(ctx, t.TrackerID, now.Add(400*24*time.Hour), &now, 100, "")
	if err != nil {
		return err
	}
	if len(ahead) != 0 {
		return fmt.Errorf("expected nothing still waiting ahead of %q, but %d occurrences are", tracker, len(ahead))
	}
	return nil
}

// ---- Schedules ------------------------------------------------------------------

func (w *world) readsSchedules(ctx context.Context, label, tracker string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodGet, "/v1/trackers/"+t.TrackerID+"/schedules", nil)
}

// schedulesNamed checks the labelled schedule reads by its label and the
// unlabelled one by a name made from itself: its days and time, never just the
// tracker's name.
func (w *world) schedulesNamed(labelled, tracker string) error {
	scs, err := decodeLast[[]scheduleView](w)
	if err != nil {
		return err
	}
	want := fmt.Sprintf("two schedules: %q, and one named for its days and time rather than %q", labelled, tracker)
	if len(scs) != 2 || scs[0].Name != labelled {
		return w.unexpected(want)
	}
	derived := scs[1].Name
	if strings.TrimSpace(derived) == "" || strings.Contains(derived, tracker) ||
		!strings.Contains(derived, "Mon") || !strings.Contains(derived, "Wed") || !strings.Contains(derived, "Fri") ||
		!strings.Contains(derived, "8:00") {
		return w.unexpected(want)
	}
	return nil
}
