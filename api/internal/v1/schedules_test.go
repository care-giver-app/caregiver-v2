package v1

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
)

// entryIDs lists every entry of the tracker, past and future, newest first.
func entryIDs(t *testing.T, f *trackerFixture, trackerID string) []string {
	t.Helper()
	es := trackerEntries(t, f, trackerID)
	ids := make([]string, 0, len(es))
	for _, e := range es {
		ids = append(ids, e.EntryID)
	}
	return ids
}

func trackerEntries(t *testing.T, f *trackerFixture, trackerID string) []domain.Entry {
	t.Helper()
	es, _, err := f.l.Stores.Entries.ListByTrackerTimeline(context.Background(), trackerID, trackerNow.Add(400*24*time.Hour), nil, 100, "")
	if err != nil {
		t.Fatal(err)
	}
	return es
}

// occurrences lists the tracker's scheduled entries still to come, soonest
// first, by occurrence_local.
func occurrences(t *testing.T, f *trackerFixture, trackerID string) []string {
	t.Helper()
	var out []string
	es := trackerEntries(t, f, trackerID)
	for i := len(es) - 1; i >= 0; i-- {
		if e := es[i]; e.State == domain.EntryScheduled && e.OccurrenceAt.After(trackerNow) {
			out = append(out, e.OccurrenceLocal)
		}
	}
	return out
}

// medTracker is a tracker on r1 with a field of every kind a plan can fill.
func medTracker(id string) domain.Tracker {
	tr := weightTracker(id, "Medication")
	tr.Fields = []domain.Field{
		{FieldID: "dose", Label: "Dose", Type: domain.FieldNumber, Unit: "mg", Status: domain.FieldActive},
		{FieldID: "pills", Label: "Pills", Type: domain.FieldChoice, Multiple: true, Status: domain.FieldActive, Options: []domain.ChoiceOption{
			{OptionID: "a", Label: "A", Status: domain.OptionActive}, {OptionID: "b", Label: "B", Status: domain.OptionActive},
			{OptionID: "old", Label: "Old", Status: domain.OptionRetired},
		}},
		{FieldID: "old-field", Label: "Old", Type: domain.FieldText, Status: domain.FieldPaused},
	}
	return tr
}

const dailyAt8 = `{"rule":{"freq":"weekly","interval":1,"by_day":["MO","TU","WE","TH","FR","SA","SU"]},"time":"08:00",
	"planned_values":{"dose":5,"pills":["a","b"]},"unrecorded_alert":true}`

func TestSchedules_Add(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	f.put(t, f.l.Names.Trackers, medTracker("tr1"))
	arch := medTracker("tr-arch")
	arch.ReceiverID = "r-arch"
	f.put(t, f.l.Names.Trackers, arch)
	post := func(as, tracker, body string) *httptest.ResponseRecorder {
		return f.do(as, http.MethodPost, "/v1/trackers/"+tracker+"/schedules", body)
	}

	for name, body := range map[string]string{
		"not json":           `{`,
		"no rule":            `{"time":"08:00","planned_values":{},"unrecorded_alert":false}`,
		"no unrecorded flag": `{"rule":{"freq":"weekly","interval":1,"by_day":["MO"]},"time":"08:00","planned_values":{}}`,
		"no planned values":  `{"rule":{"freq":"weekly","interval":1,"by_day":["MO"]},"time":"08:00","unrecorded_alert":false}`,
		"freq":               strings.Replace(dailyAt8, `"weekly"`, `"monthly"`, 1),
		"interval":           strings.Replace(dailyAt8, `"interval":1`, `"interval":0`, 1),
		"no days":            `{"rule":{"freq":"weekly","interval":1,"by_day":[]},"time":"08:00","planned_values":{},"unrecorded_alert":false}`,
		"time":               strings.Replace(dailyAt8, `"08:00"`, `"8am"`, 1),
		"ends yesterday":     strings.Replace(dailyAt8, `"time"`, `"ends_on":"2026-11-07","time"`, 1),
		"label":              strings.Replace(dailyAt8, `"time"`, `"label":"`+strings.Repeat("x", 101)+`","time"`, 1),
		"unknown field":      strings.Replace(dailyAt8, `"dose":5`, `"nope":5`, 1),
		"paused field":       strings.Replace(dailyAt8, `"dose":5`, `"old-field":"x"`, 1),
		"wrong kind":         strings.Replace(dailyAt8, `"dose":5`, `"dose":"5"`, 1),
		"retired option":     strings.Replace(dailyAt8, `["a","b"]`, `["old"]`, 1),
	} {
		if rec := post("admin", "tr1", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
	for _, c := range []struct {
		as, tracker string
		want        int
	}{{"cg", "tr1", http.StatusForbidden}, {"out", "tr1", http.StatusForbidden}, {"admin", "nope", http.StatusNotFound}, {"admin", "tr-arch", http.StatusNotFound}} {
		if rec := post(c.as, c.tracker, dailyAt8); rec.Code != c.want {
			t.Errorf("%s on %s: code=%d, want %d", c.as, c.tracker, rec.Code, c.want)
		}
	}
	if ids := entryIDs(t, f, "tr1"); len(ids) != 0 {
		t.Fatalf("refused adds generated entries: %v", ids)
	}

	// Saved at noon: today's 08:00 is not made; tomorrow's through the horizon are.
	rec := post("admin", "tr1", dailyAt8)
	sc := decode[trackerSchedule](t, rec)
	if rec.Code != http.StatusCreated || sc.ScheduleID != "new-1" || sc.Name != "Every day at 8:00 AM" || sc.Label != "" ||
		sc.StartsOn != "2026-11-08" || sc.Time != "08:00" || !sc.UnrecordedAlert || sc.PlannedValues["dose"] != 5.0 {
		t.Fatalf("add: code=%d %+v", rec.Code, sc)
	}
	occs := occurrences(t, f, "tr1")
	if len(occs) != 14 || occs[0] != "2026-11-09T08:00" || occs[13] != "2026-11-22T08:00" {
		t.Fatalf("occurrences: %v", occs)
	}
	first := trackerEntries(t, f, "tr1")[13]
	if first.EntryID != generate.EntryID("new-1", "2026-11-09T08:00") || first.ScheduleID != "new-1" || first.CreatedBy != "admin" ||
		first.Values["dose"] != 5.0 || first.PlannedValues["dose"] != 5.0 || !first.UnrecordedAlert || first.OpenAt == nil {
		t.Fatalf("first occurrence: %+v", first)
	}
	stored, _ := f.l.Stores.Schedules.Get(ctx, "new-1")
	if stored.GeneratedThrough != "2026-11-22" || stored.CreatedBy != "admin" {
		t.Fatalf("stored: %+v", stored)
	}
	if d := decode[trackerDetail](t, f.do("cg", http.MethodGet, "/v1/trackers/tr1", "")); d.ScheduleCount != 1 {
		t.Fatalf("schedule_count: %d", d.ScheduleCount)
	}

	// Saved before today's time: today's is the first.
	f.put(t, f.l.Names.Trackers, medTracker("tr2"))
	rec = post("admin", "tr2", `{"label":" Lunch ","rule":{"freq":"weekly","interval":1,"by_day":["SU"]},"time":"13:00","planned_values":{},"unrecorded_alert":false}`)
	if sc := decode[trackerSchedule](t, rec); rec.Code != http.StatusCreated || sc.Name != "Lunch" || sc.Label != "Lunch" {
		t.Fatalf("lunch: code=%d %+v", rec.Code, sc)
	}
	if occs := occurrences(t, f, "tr2"); fmt.Sprint(occs) != "[2026-11-08T13:00 2026-11-15T13:00]" {
		t.Fatalf("lunch occurrences: %v", occs)
	}
}

func TestSchedules_AddOverGap(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	tr := medTracker("tr1")
	tr.GapHours = intp(72)
	f.put(t, f.l.Names.Trackers, tr)

	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/schedules", dailyAt8); rec.Code != http.StatusConflict {
		t.Fatalf("over a gap: code=%d body=%s", rec.Code, rec.Body.String())
	}
	if n, _ := f.l.Stores.Schedules.CountLiveByTracker(ctx, "tr1"); n != 0 {
		t.Fatalf("a refused schedule was written")
	}
	if got, _ := f.l.Stores.Trackers.Get(ctx, "tr1"); got.GapHours == nil {
		t.Fatal("a refused schedule took the gap")
	}

	body := strings.Replace(dailyAt8, `"time"`, `"replace_gap":true,"time"`, 1)
	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/schedules", body); rec.Code != http.StatusCreated {
		t.Fatalf("replacing the gap: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[trackerDetail](t, f.do("admin", http.MethodGet, "/v1/trackers/tr1", ""))
	if d.GapHours != nil || d.ScheduleCount != 1 || d.Name != "Medication" || len(d.Fields) != 3 {
		t.Fatalf("after replacing the gap: %+v", d)
	}
	if occs := occurrences(t, f, "tr1"); len(occs) != 14 {
		t.Fatalf("occurrences: %v", occs)
	}
}

func TestSchedules_PausedTrackerGeneratesOnResume(t *testing.T) {
	f := newTrackerFixture(t)
	tr := medTracker("tr1")
	paused := trackerNow.Add(-24 * time.Hour)
	tr.Status, tr.PausedAt, tr.PausedBy = domain.TrackerPaused, &paused, "admin"
	f.put(t, f.l.Names.Trackers, tr)

	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/schedules", dailyAt8); rec.Code != http.StatusCreated {
		t.Fatalf("add to paused: code=%d body=%s", rec.Code, rec.Body.String())
	}
	if ids := entryIDs(t, f, "tr1"); len(ids) != 0 {
		t.Fatalf("a paused tracker generated: %v", ids)
	}
	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/resume", ""); rec.Code != http.StatusOK {
		t.Fatalf("resume: %d", rec.Code)
	}
	if occs := occurrences(t, f, "tr1"); len(occs) != 14 || occs[0] != "2026-11-09T08:00" {
		t.Fatalf("after resume: %v", occs)
	}
	// Pausing again takes them back.
	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/pause", ""); rec.Code != http.StatusOK {
		t.Fatalf("pause: %d", rec.Code)
	}
	if occs := occurrences(t, f, "tr1"); len(occs) != 0 {
		t.Fatalf("after pause: %v", occs)
	}
}

func TestSchedules_Change(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	f.put(t, f.l.Names.Trackers, medTracker("tr1"))
	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/schedules", dailyAt8); rec.Code != http.StatusCreated {
		t.Fatalf("add: %d", rec.Code)
	}
	// Yesterday's went unrecorded; tomorrow's was logged early.
	f.put(t, f.l.Names.Entries, scheduled("yesterday", "tr1", "new-1", trackerNow.Add(-28*time.Hour)))
	early := trackerEntries(t, f, "tr1")[13]
	early.State, early.OpenAt, early.LoggedBy, early.OccurredAt = domain.EntryLogged, nil, "cg", &trackerNow
	early.TimelineAt = trackerNow
	f.put(t, f.l.Names.Entries, early)

	put := func(as, id, body string) *httptest.ResponseRecorder {
		return f.do(as, http.MethodPut, "/v1/schedules/"+id, body)
	}
	change := `{"label":"Mornings","rule":{"freq":"weekly","interval":1,"by_day":["MO"]},"time":"09:00",
		"ends_on":"2026-12-31","planned_values":{"dose":10},"unrecorded_alert":false}`
	if rec := put("cg", "new-1", change); rec.Code != http.StatusForbidden {
		t.Errorf("caregiver: code=%d", rec.Code)
	}
	if rec := put("out", "new-1", change); rec.Code != http.StatusForbidden {
		t.Errorf("outsider: code=%d", rec.Code)
	}
	if rec := put("admin", "nope", change); rec.Code != http.StatusNotFound {
		t.Errorf("unknown: code=%d", rec.Code)
	}
	if rec := put("admin", "new-1", strings.Replace(change, `"dose":10`, `"dose":true`, 1)); rec.Code != http.StatusBadRequest {
		t.Errorf("bad value: code=%d", rec.Code)
	}
	if rec := put("admin", "new-1", strings.Replace(change, `"2026-12-31"`, `"2026-11-01"`, 1)); rec.Code != http.StatusBadRequest {
		t.Errorf("ends before today: code=%d", rec.Code)
	}
	if occs := occurrences(t, f, "tr1"); len(occs) != 13 {
		t.Fatalf("a refused change moved occurrences: %v", occs)
	}

	rec := put("admin", "new-1", change)
	sc := decode[trackerSchedule](t, rec)
	if rec.Code != http.StatusOK || sc.Name != "Mornings" || sc.Time != "09:00" || sc.StartsOn != "2026-11-08" ||
		sc.EndsOn != "2026-12-31" || sc.UnrecordedAlert || sc.PlannedValues["dose"] != 10.0 {
		t.Fatalf("change: code=%d %+v", rec.Code, sc)
	}
	if occs := occurrences(t, f, "tr1"); fmt.Sprint(occs) != "[2026-11-09T09:00 2026-11-16T09:00]" {
		t.Fatalf("occurrences after the change: %v", occs)
	}
	for _, e := range trackerEntries(t, f, "tr1") {
		switch e.EntryID {
		case "yesterday":
		case early.EntryID:
			if e.State != domain.EntryLogged {
				t.Errorf("the early log was touched: %+v", e)
			}
		default:
			if e.Values["dose"] != 10.0 || e.UnrecordedAlert {
				t.Errorf("new occurrence not from the new plan: %+v", e)
			}
		}
	}
	if ids := entryIDs(t, f, "tr1"); len(ids) != 4 {
		t.Fatalf("entries after the change: %v", ids)
	}
	if got, _ := f.l.Stores.Schedules.Get(ctx, "new-1"); got.GeneratedThrough != "2026-11-16" {
		t.Fatalf("generated_through: %q", got.GeneratedThrough)
	}

	// A removed schedule cannot be changed.
	if rec := f.do("admin", http.MethodDelete, "/v1/schedules/new-1", ""); rec.Code != http.StatusNoContent {
		t.Fatalf("remove: %d", rec.Code)
	}
	if rec := put("admin", "new-1", change); rec.Code != http.StatusNotFound {
		t.Errorf("removed: code=%d", rec.Code)
	}
}

func TestSchedules_Remove(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	f.put(t, f.l.Names.Trackers, medTracker("tr1"))
	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/schedules",
		strings.Replace(dailyAt8, `"time"`, `"label":"Morning dose","time"`, 1)); rec.Code != http.StatusCreated {
		t.Fatalf("add: %d", rec.Code)
	}
	past := trackerNow.Add(-28 * time.Hour)
	f.put(t, f.l.Names.Entries, scheduled("unrecorded", "tr1", "new-1", past))
	lg := logged("logged", "tr1", "cg", trackerNow.Add(-52*time.Hour), nil)
	lg.ScheduleID = "new-1"
	f.put(t, f.l.Names.Entries, lg)

	del := func(as, id string) int { return f.do(as, http.MethodDelete, "/v1/schedules/"+id, "").Code }
	if code := del("cg", "new-1"); code != http.StatusForbidden {
		t.Errorf("caregiver: %d", code)
	}
	if code := del("out", "new-1"); code != http.StatusForbidden {
		t.Errorf("outsider: %d", code)
	}
	if code := del("admin", "nope"); code != http.StatusNotFound {
		t.Errorf("unknown: %d", code)
	}
	if n, _ := f.l.Stores.Schedules.CountLiveByTracker(ctx, "tr1"); n != 1 {
		t.Fatal("a refused removal removed it")
	}

	if code := del("admin", "new-1"); code != http.StatusNoContent {
		t.Fatalf("remove: %d", code)
	}
	if code := del("admin", "new-1"); code != http.StatusNotFound {
		t.Errorf("removed twice: %d", code)
	}
	if ids := entryIDs(t, f, "tr1"); fmt.Sprint(ids) != "[unrecorded logged]" {
		t.Fatalf("entries after removal: %v", ids)
	}
	if d := decode[trackerDetail](t, f.do("cg", http.MethodGet, "/v1/trackers/tr1", "")); d.ScheduleCount != 0 {
		t.Fatalf("schedule_count: %d", d.ScheduleCount)
	}
	// What it made still names it.
	page := decode[entryPage](t, f.do("cg", http.MethodGet, "/v1/trackers/tr1/entries", ""))
	if len(page.Entries) != 2 || page.Entries[0].ScheduleName != "Morning dose" || page.Entries[1].ScheduleName != "Morning dose" {
		t.Fatalf("entries: %+v", page.Entries)
	}
}
