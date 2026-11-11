package v1

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// newHomeFixture is the tracker fixture with Home's reads on its mux, at
// trackerNow: noon on 8 November in Chicago, whose day runs 06:00Z on the 8th
// to 06:00Z on the 9th.
func newHomeFixture(t *testing.T) *trackerFixture {
	t.Helper()
	f := newTrackerFixture(t)
	h := NewHome(f.l.Stores)
	h.now = func() time.Time { return trackerNow }
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/attention", h.Attention)
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/coming-up", h.ComingUp)
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/timeline", h.Timeline)
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/waiting", h.Waiting)
	f.mux.HandleFunc("GET /v1/entries/{entryId}", h.Entry)
	f.mux.HandleFunc("GET /v1/journal-notes/{noteId}", h.JournalNote)
	return f
}

func paused(tr domain.Tracker) domain.Tracker {
	at := trackerNow.Add(-24 * time.Hour)
	tr.Status, tr.PausedAt, tr.PausedBy = domain.TrackerPaused, &at, "admin"
	return tr
}

func journalNote(id, author string, at time.Time) domain.JournalNote {
	return domain.JournalNote{NoteID: id, ReceiverID: "r1", TeamID: "t1", At: at, Body: "slept well", Author: author, CreatedAt: at}
}

func (f *trackerFixture) seed(t *testing.T, trackers []domain.Tracker, entries []domain.Entry, notes ...domain.JournalNote) {
	t.Helper()
	for _, tr := range trackers {
		f.put(t, f.l.Names.Trackers, tr)
	}
	for _, e := range entries {
		f.put(t, f.l.Names.Entries, e)
	}
	for _, n := range notes {
		f.put(t, f.l.Names.JournalNotes, n)
	}
}

func receiverEntryIDs(rs []receiverEntry) string {
	var s []string
	for _, r := range rs {
		s = append(s, r.Tracker.TrackerID+"/"+r.Entry.EntryID+":"+r.Entry.State)
	}
	return fmt.Sprint(s)
}

func TestHome_authz(t *testing.T) {
	f := newHomeFixture(t)
	arch := weightTracker("tr-arch", "Weight")
	arch.ReceiverID = "r-arch"
	archEntry := logged("e-arch", "tr-arch", "admin", trackerNow.Add(-time.Hour), nil)
	archEntry.ReceiverID = "r-arch"
	archNote := journalNote("n-arch", "admin", trackerNow.Add(-time.Hour))
	archNote.ReceiverID = "r-arch"
	f.seed(t, []domain.Tracker{weightTracker("tr1", "Weight"), arch},
		[]domain.Entry{logged("e1", "tr1", "cg", trackerNow.Add(-time.Hour), nil), archEntry},
		journalNote("n1", "cg", trackerNow.Add(-time.Hour)), archNote)

	reads := []string{
		"/v1/receivers/r1/attention", "/v1/receivers/r1/coming-up", "/v1/receivers/r1/timeline?date=2026-11-08",
		"/v1/receivers/r1/waiting", "/v1/entries/e1", "/v1/journal-notes/n1",
	}
	for _, p := range reads {
		if rec := f.do("out", http.MethodGet, p, ""); rec.Code != http.StatusForbidden {
			t.Errorf("non-member %s: code=%d", p, rec.Code)
		}
		if rec := f.do("cg", http.MethodGet, p, ""); rec.Code != http.StatusOK {
			t.Errorf("caregiver %s: code=%d body=%s", p, rec.Code, rec.Body.String())
		}
		rec := httptest.NewRecorder()
		f.mux.ServeHTTP(rec, jsonRequest(http.MethodGet, p, ""))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("no caller %s: code=%d", p, rec.Code)
		}
	}
	for _, p := range []string{
		"/v1/receivers/nope/attention", "/v1/receivers/r-arch/attention", "/v1/receivers/r-arch/coming-up",
		"/v1/receivers/r-arch/timeline?date=2026-11-08", "/v1/receivers/r-arch/waiting",
		"/v1/entries/nope", "/v1/entries/e-arch", "/v1/journal-notes/nope", "/v1/journal-notes/n-arch",
	} {
		if rec := f.do("admin", http.MethodGet, p, ""); rec.Code != http.StatusNotFound {
			t.Errorf("unknown %s: code=%d", p, rec.Code)
		}
	}
}

func TestHome_Attention(t *testing.T) {
	f := newHomeFixture(t)
	gap := weightTracker("tr-gap", "Walk")
	gap.Fields, gap.GapHours = nil, intp(24)
	f.seed(t,
		[]domain.Tracker{medTracker("tr-med"), weightTracker("tr-w", "Weight"), weightTracker("tr-w2", "Weight 2"), gap,
			paused(medTracker("tr-paused"))},
		[]domain.Entry{
			// Two unrecorded doses: the more recent one stands for the tracker.
			scheduled("med-5h", "tr-med", "", trackerNow.Add(-5*time.Hour)),
			scheduled("med-1h", "tr-med", "", trackerNow.Add(-time.Hour)),
			// Unrecorded exactly 48h ago has left the list.
			scheduled("med-48h", "tr-med", "", trackerNow.Add(-domain.UnrecordedWindow)),
			logged("w-old", "tr-w", "admin", trackerNow.Add(-3*time.Hour), map[string]any{"w": 500.0}),
			logged("w2-new", "tr-w2", "admin", trackerNow.Add(-2*time.Hour), map[string]any{"w": 50.0}),
			scheduled("paused-1h", "tr-paused", "", trackerNow.Add(-time.Hour)),
			// Corrupt data: its tracker is gone. Left out, not a failed read.
			scheduled("orphan-1h", "tr-gone", "", trackerNow.Add(-time.Hour)),
		})

	get := func(q string) ([]map[string]any, int) {
		rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/attention"+q, "")
		if rec.Code != http.StatusOK {
			return nil, rec.Code
		}
		return decode[[]map[string]any](t, rec), rec.Code
	}
	summary := func(items []map[string]any) string {
		var s []string
		for _, it := range items {
			tr, a := it["tracker"].(map[string]any), it["attention"].(map[string]any)
			s = append(s, fmt.Sprintf("%s:%s:%v", tr["tracker_id"], a["kind"], a["entry_id"]))
		}
		return fmt.Sprint(s)
	}

	all, _ := get("?limit=50")
	if summary(all) != "[tr-med:unrecorded:med-1h tr-w2:out_of_range:w2-new tr-w:out_of_range:w-old tr-gap:gap:<nil>]" {
		t.Fatalf("all: %s", summary(all))
	}
	if all[1]["field_label"] != "Weight" || all[1]["unit"] != "lb" {
		t.Errorf("out_of_range labels: %v", all[1])
	}
	if _, ok := all[0]["field_label"]; ok {
		t.Errorf("unrecorded carries field_label: %v", all[0])
	}
	if tr := all[0]["tracker"].(map[string]any); tr["name"] != "Medication" || tr["icon"] != "scalemass" || tr["color"] != "#4F8EF7" {
		t.Errorf("badge: %v", tr)
	}
	if def, _ := get(""); summary(def) != "[tr-med:unrecorded:med-1h tr-w2:out_of_range:w2-new tr-w:out_of_range:w-old]" {
		t.Errorf("default limit 3: %s", summary(def))
	}
	if one, _ := get("?limit=1"); len(one) != 1 {
		t.Errorf("limit=1: %d", len(one))
	}
	for _, q := range []string{"?limit=0", "?limit=51", "?limit=x"} {
		if _, code := get(q); code != http.StatusBadRequest {
			t.Errorf("%s: code=%d", q, code)
		}
	}
	if rec := f.do("cg", http.MethodGet, "/v1/receivers/r0/attention", ""); strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Errorf("nothing needs attention: %s", rec.Body.String())
	}
}

func TestHome_ComingUp(t *testing.T) {
	f := newHomeFixture(t)
	appt := weightTracker("tr-appt", "Appointment")
	appt.Fields = nil
	f.put(t, f.l.Names.Schedules, domain.Schedule{ScheduleID: "s-am", TrackerID: "tr-med", ReceiverID: "r1", TeamID: "t1",
		Label: "Morning meds", Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "08:00",
		StartsOn: "2026-11-01", CreatedBy: "admin", CreatedAt: trackerNow.Add(-10 * 24 * time.Hour)})
	f.seed(t,
		[]domain.Tracker{medTracker("tr-med"), appt, paused(medTracker("tr-paused"))},
		[]domain.Entry{
			scheduled("med-past", "tr-med", "s-am", trackerNow.Add(-time.Hour)),
			scheduled("med-26h", "tr-med", "s-am", trackerNow.Add(26*time.Hour)),
			scheduled("med-2h", "tr-med", "s-am", trackerNow.Add(2*time.Hour)),
			scheduled("appt-5d", "tr-appt", "", trackerNow.Add(5*24*time.Hour)),
			scheduled("paused-1h", "tr-paused", "", trackerNow.Add(time.Hour)),
		})

	get := func(q string) ([]receiverEntry, int) {
		rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/coming-up"+q, "")
		if rec.Code != http.StatusOK {
			return nil, rec.Code
		}
		return decode[[]receiverEntry](t, rec), rec.Code
	}
	all, _ := get("")
	if receiverEntryIDs(all) != "[tr-med/med-2h:scheduled tr-appt/appt-5d:scheduled]" {
		t.Fatalf("all: %s", receiverEntryIDs(all))
	}
	if all[0].Entry.ScheduleName != "Morning meds" || all[0].Tracker.Name != "Medication" || all[0].Entry.At != "2026-11-08T20:00:00Z" {
		t.Errorf("first: %+v", all[0])
	}
	if one, _ := get("?limit=1"); receiverEntryIDs(one) != "[tr-med/med-2h:scheduled]" {
		t.Errorf("limit=1: %s", receiverEntryIDs(one))
	}
	for _, q := range []string{"?limit=0", "?limit=101", "?limit=x"} {
		if _, code := get(q); code != http.StatusBadRequest {
			t.Errorf("%s: code=%d", q, code)
		}
	}
	if rec := f.do("cg", http.MethodGet, "/v1/receivers/r0/coming-up", ""); strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Errorf("nothing ahead: %s", rec.Body.String())
	}
}

func TestHome_Waiting(t *testing.T) {
	f := newHomeFixture(t)
	skipped := scheduled("med-skipped", "tr-med", "", trackerNow.Add(-2*time.Hour))
	skipAt := trackerNow.Add(-time.Hour)
	skipped.State, skipped.OpenAt, skipped.SkippedBy, skipped.SkippedAt = domain.EntrySkipped, nil, "cg", &skipAt
	f.seed(t,
		[]domain.Tracker{medTracker("tr-med"), paused(medTracker("tr-paused"))},
		[]domain.Entry{
			scheduled("med-48h", "tr-med", "", trackerNow.Add(-domain.UnrecordedWindow)),
			scheduled("med-47h", "tr-med", "", trackerNow.Add(-47*time.Hour)),
			scheduled("med-2h-later", "tr-med", "", trackerNow.Add(2*time.Hour)),
			scheduled("med-1h", "tr-med", "", trackerNow.Add(-time.Hour)),
			skipped,
			// 01:00 on the 9th in Chicago: tomorrow, not the rest of today.
			scheduled("med-tomorrow", "tr-med", "", time.Date(2026, 11, 9, 7, 0, 0, 0, time.UTC)),
			// 23:59 on the 8th in Chicago is still today.
			scheduled("med-late", "tr-med", "", time.Date(2026, 11, 9, 5, 59, 0, 0, time.UTC)),
			scheduled("paused-1h", "tr-paused", "", trackerNow.Add(-time.Hour)),
		})
	rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/waiting", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	got := decode[[]receiverEntry](t, rec)
	want := "[tr-med/med-47h:unrecorded tr-med/med-1h:unrecorded tr-med/med-2h-later:scheduled tr-med/med-late:scheduled]"
	if receiverEntryIDs(got) != want {
		t.Fatalf("waiting: %s", receiverEntryIDs(got))
	}
	if rec := f.do("cg", http.MethodGet, "/v1/receivers/r0/waiting", ""); strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Errorf("nothing waiting: %s", rec.Body.String())
	}
}

func TestHome_Timeline(t *testing.T) {
	f := newHomeFixture(t)
	skipped := scheduled("skipped", "tr-med", "", time.Date(2026, 11, 8, 14, 0, 0, 0, time.UTC))
	skipAt := trackerNow.Add(-time.Hour)
	skipped.State, skipped.OpenAt, skipped.SkippedBy, skipped.SkippedAt = domain.EntrySkipped, nil, "cg", &skipAt
	edited := journalNote("n-edited", "gone", time.Date(2026, 11, 8, 15, 0, 0, 0, time.UTC))
	editedAt := trackerNow.Add(-30 * time.Minute)
	edited.UpdatedBy, edited.UpdatedAt = "cg", &editedAt
	f.seed(t,
		[]domain.Tracker{medTracker("tr-med"), paused(weightTracker("tr-paused", "Weight"))},
		[]domain.Entry{
			logged("prev-day", "tr-med", "admin", time.Date(2026, 11, 8, 5, 59, 0, 0, time.UTC), nil),
			logged("first", "tr-med", "admin", time.Date(2026, 11, 8, 6, 0, 0, 0, time.UTC), nil),
			skipped,
			scheduled("unrecorded", "tr-med", "", trackerNow.Add(-time.Hour)),
			scheduled("to-come", "tr-med", "", trackerNow.Add(2*time.Hour)),
			logged("paused-log", "tr-paused", "admin", time.Date(2026, 11, 8, 16, 0, 0, 0, time.UTC), map[string]any{"w": 150.0}),
			// Corrupt data: its tracker is gone. Left out, not a failed day.
			logged("orphan", "tr-gone", "admin", time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC), nil),
		},
		journalNote("n-am", "cg", time.Date(2026, 11, 8, 10, 0, 0, 0, time.UTC)),
		edited,
		journalNote("n-tie", "admin", time.Date(2026, 11, 8, 16, 0, 0, 0, time.UTC)),
	)

	rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/timeline?date=2026-11-08", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	day := decode[dayTimeline](t, rec)
	var got []string
	for _, it := range day.Items {
		switch it.Kind {
		case "entry":
			got = append(got, "entry:"+it.Entry.EntryID+":"+it.Entry.State)
			if it.Tracker == nil || it.Tracker.TrackerID != it.Entry.TrackerID || it.At != it.Entry.At {
				t.Errorf("entry item: %+v", it)
			}
		case "note":
			got = append(got, "note:"+it.Note.NoteID)
			if it.Tracker != nil || it.Entry != nil || it.At != it.Note.At {
				t.Errorf("note item: %+v", it)
			}
		}
	}
	want := "[entry:first:logged note:n-am entry:skipped:skipped note:n-edited entry:paused-log:logged note:n-tie entry:unrecorded:unrecorded]"
	if day.Date != "2026-11-08" || fmt.Sprint(got) != want {
		t.Fatalf("date=%s items=%v", day.Date, got)
	}
	if n := day.Items[3].Note; n.AuthorName != formerCaregiver || n.UpdatedByName != "Cal" || n.UpdatedAt == nil ||
		*n.UpdatedAt != "2026-11-08T17:30:00Z" || n.Body != "slept well" {
		t.Errorf("edited note: %+v", n)
	}
	if n := day.Items[1].Note; n.AuthorName != "Cal" || n.UpdatedByName != "" || n.UpdatedAt != nil {
		t.Errorf("unedited note: %+v", n)
	}
	if e := day.Items[2].Entry; e.ByName != "Cal" {
		t.Errorf("skipped by: %+v", e)
	}

	if rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/timeline?date=2026-11-01", ""); rec.Code != http.StatusOK ||
		!strings.Contains(rec.Body.String(), `"items":[]`) {
		t.Errorf("empty day: %d %s", rec.Code, rec.Body.String())
	}
	if rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/timeline?date=2026-11-07", ""); !strings.Contains(rec.Body.String(), "prev-day") {
		t.Errorf("the 7th in Chicago holds 05:59Z on the 8th: %s", rec.Body.String())
	}
	for _, q := range []string{"", "?date=", "?date=2026-11-09", "?date=2026-13-01", "?date=2026-11-8", "?date=11/08/2026"} {
		if rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/timeline"+q, ""); rec.Code != http.StatusBadRequest {
			t.Errorf("%q: code=%d", q, rec.Code)
		}
	}
}

func TestHome_Entry(t *testing.T) {
	f := newHomeFixture(t)
	tr := weightTracker("tr-w", "Weight")
	tr.Fields = append(tr.Fields, domain.Field{FieldID: "old", Label: "Old", Type: domain.FieldText, Status: domain.FieldPaused})
	f.put(t, f.l.Names.Schedules, domain.Schedule{ScheduleID: "s-am", TrackerID: "tr-w", ReceiverID: "r1", TeamID: "t1",
		Label: "Weigh-in", Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "08:00",
		StartsOn: "2026-11-01", CreatedBy: "admin", CreatedAt: trackerNow.Add(-10 * 24 * time.Hour)})

	high := logged("high", "tr-w", "admin", trackerNow.Add(-2*time.Hour), map[string]any{"w": 500.0})
	loggedAt, updatedAt := trackerNow.Add(-90*time.Minute), trackerNow.Add(-time.Hour)
	high.LoggedAt, high.UpdatedBy, high.UpdatedAt = &loggedAt, "gone", &updatedAt
	planned := scheduled("planned", "tr-w", "s-am", trackerNow.Add(-time.Hour))
	planned.UnrecordedAlert = true
	skipped := scheduled("skipped", "tr-w", "", trackerNow.Add(-3*time.Hour))
	skipAt := trackerNow.Add(-2 * time.Hour)
	skipped.State, skipped.OpenAt, skipped.SkippedBy, skipped.SkippedAt = domain.EntrySkipped, nil, "cg", &skipAt
	f.seed(t, []domain.Tracker{paused(tr)}, []domain.Entry{high, planned, skipped})

	get := func(id string) map[string]any {
		rec := f.do("cg", http.MethodGet, "/v1/entries/"+id, "")
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: code=%d body=%s", id, rec.Code, rec.Body.String())
		}
		return decode[map[string]any](t, rec)
	}

	d := get("high")
	e := d["entry"].(map[string]any)
	if e["state"] != "logged" || e["by_name"] != "Ann" || d["planned"] != false || d["settled_at"] != "2026-11-08T16:30:00Z" ||
		d["updated_by_name"] != formerCaregiver || d["updated_at"] != "2026-11-08T17:00:00Z" {
		t.Errorf("logged: %v", d)
	}
	for _, k := range []string{"occurrence_at", "unrecorded_alert"} {
		if _, ok := d[k]; ok {
			t.Errorf("ad hoc entry carries %s", k)
		}
	}
	if fields := d["fields"].([]any); len(fields) != 2 || fields[1].(map[string]any)["status"] != "paused" {
		t.Errorf("fields (paused included): %v", d["fields"])
	}
	oor := d["out_of_range"].([]any)
	if len(oor) != 1 || fmt.Sprint(oor[0]) != "map[field_id:w range:map[high:400 low:80] value:500]" {
		t.Errorf("out_of_range: %v", oor)
	}
	if tr := d["tracker"].(map[string]any); tr["tracker_id"] != "tr-w" || tr["name"] != "Weight" {
		t.Errorf("badge: %v", tr)
	}

	d = get("planned")
	e = d["entry"].(map[string]any)
	if e["state"] != "unrecorded" || e["schedule_name"] != "Weigh-in" || d["planned"] != true ||
		d["occurrence_at"] != "2026-11-08T17:00:00Z" || d["unrecorded_alert"] != true {
		t.Errorf("planned: %v", d)
	}
	for _, k := range []string{"settled_at", "updated_by_name", "updated_at"} {
		if _, ok := d[k]; ok {
			t.Errorf("waiting entry carries %s", k)
		}
	}
	if oor, ok := d["out_of_range"].([]any); !ok || len(oor) != 0 {
		t.Errorf("out_of_range must be [] not null: %v", d["out_of_range"])
	}

	d = get("skipped")
	if e := d["entry"].(map[string]any); e["state"] != "skipped" || e["by_name"] != "Cal" ||
		d["settled_at"] != "2026-11-08T16:00:00Z" || d["planned"] != true || d["unrecorded_alert"] != false {
		t.Errorf("skipped: %v", d)
	}
}

func TestHome_JournalNote(t *testing.T) {
	f := newHomeFixture(t)
	edited := journalNote("n-edited", "nobody", trackerNow.Add(-3*time.Hour))
	editedAt := trackerNow.Add(-time.Hour)
	edited.UpdatedBy, edited.UpdatedAt = "admin", &editedAt
	f.seed(t, nil, nil, journalNote("n1", "cg", trackerNow.Add(-2*time.Hour)), edited)

	rec := f.do("admin", http.MethodGet, "/v1/journal-notes/n1", "")
	n := decode[map[string]any](t, rec)
	if rec.Code != http.StatusOK || n["note_id"] != "n1" || n["receiver_id"] != "r1" || n["author_name"] != "Cal" ||
		n["at"] != "2026-11-08T16:00:00Z" || n["created_at"] != "2026-11-08T16:00:00Z" || n["body"] != "slept well" {
		t.Errorf("note: %d %v", rec.Code, n)
	}
	for _, k := range []string{"updated_by_name", "updated_at"} {
		if _, ok := n[k]; ok {
			t.Errorf("unedited note carries %s", k)
		}
	}
	n = decode[map[string]any](t, f.do("cg", http.MethodGet, "/v1/journal-notes/n-edited", ""))
	if n["author_name"] != formerCaregiver || n["updated_by_name"] != "Ann" || n["updated_at"] != "2026-11-08T17:00:00Z" {
		t.Errorf("edited note: %v", n)
	}
}
