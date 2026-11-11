package v1

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// newWriteFixture is the Home fixture with Home's writes on its mux too, and
// ids handed out as new-1, new-2 and so on.
func newWriteFixture(t *testing.T) *trackerFixture {
	t.Helper()
	f := newHomeFixture(t)
	h := NewHome(f.l.Stores)
	h.now = func() time.Time { return trackerNow }
	h.newID = func() string { f.ids++; return fmt.Sprintf("new-%d", f.ids) }
	f.mux.HandleFunc("POST /v1/trackers/{trackerId}/entries", h.AddEntry)
	f.mux.HandleFunc("POST /v1/entries/{entryId}/log", h.LogEntry)
	f.mux.HandleFunc("POST /v1/entries/{entryId}/skip", h.SkipEntry)
	f.mux.HandleFunc("PUT /v1/entries/{entryId}", h.ChangeEntry)
	f.mux.HandleFunc("DELETE /v1/entries/{entryId}", h.DeleteEntry)
	f.mux.HandleFunc("POST /v1/receivers/{receiverId}/journal-notes", h.AddJournalNote)
	f.mux.HandleFunc("PUT /v1/journal-notes/{noteId}", h.ChangeJournalNote)
	f.mux.HandleFunc("DELETE /v1/journal-notes/{noteId}", h.DeleteJournalNote)
	return f
}

// planned is a scheduled med occurrence with planned values.
func planned(id, tracker string, at time.Time) domain.Entry {
	e := scheduled(id, tracker, "s1", at)
	e.OccurrenceLocal = at.Format("2006-01-02T15:04")
	e.PlannedValues = map[string]any{"dose": 5.0, "pills": []any{"a"}}
	e.Values = map[string]any{"dose": 5.0, "pills": []any{"a"}}
	return e
}

func ts(t time.Time) string { return t.UTC().Format(time.RFC3339) }

func careBody(at time.Time, values, note string) string {
	return fmt.Sprintf(`{"occurred_at":%q,"values":%s,"note":%q}`, ts(at), values, note)
}

func TestEntryWrites_authz(t *testing.T) {
	f := newWriteFixture(t)
	arch := medTracker("tr-arch")
	arch.ReceiverID = "r-arch"
	archEntry := planned("e-arch", "tr-arch", trackerNow.Add(-time.Hour))
	archEntry.ReceiverID = "r-arch"
	archNote := journalNote("n-arch", "admin", trackerNow.Add(-time.Hour))
	archNote.ReceiverID = "r-arch"
	f.seed(t, []domain.Tracker{medTracker("tr1"), arch},
		[]domain.Entry{planned("e1", "tr1", trackerNow.Add(-time.Hour)), archEntry},
		journalNote("n1", "admin", trackerNow.Add(-time.Hour)), archNote)

	care := careBody(trackerNow, `{"dose":5}`, "")
	note := fmt.Sprintf(`{"at":%q,"body":"hi"}`, ts(trackerNow))
	type route struct{ method, path, body string }
	routes := func(entry, tracker, receiver, noteID string) []route {
		return []route{
			{http.MethodPost, "/v1/trackers/" + tracker + "/entries", `{"values":{}}`},
			{http.MethodPost, "/v1/entries/" + entry + "/log", care},
			{http.MethodPost, "/v1/entries/" + entry + "/skip", `{}`},
			{http.MethodPut, "/v1/entries/" + entry, care},
			{http.MethodDelete, "/v1/entries/" + entry, ""},
			{http.MethodPost, "/v1/receivers/" + receiver + "/journal-notes", note},
			{http.MethodPut, "/v1/journal-notes/" + noteID, note},
			{http.MethodDelete, "/v1/journal-notes/" + noteID, ""},
		}
	}
	for _, rt := range routes("e1", "tr1", "r1", "n1") {
		if rec := f.do("out", rt.method, rt.path, rt.body); rec.Code != http.StatusForbidden {
			t.Errorf("non-member %s %s: code=%d", rt.method, rt.path, rec.Code)
		}
		rec := httptest.NewRecorder()
		f.mux.ServeHTTP(rec, jsonRequest(rt.method, rt.path, rt.body))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("no caller %s %s: code=%d", rt.method, rt.path, rec.Code)
		}
	}
	for _, ids := range [][4]string{{"nope", "nope", "nope", "nope"}, {"e-arch", "tr-arch", "r-arch", "n-arch"}} {
		for _, rt := range routes(ids[0], ids[1], ids[2], ids[3]) {
			if rec := f.do("admin", rt.method, rt.path, rt.body); rec.Code != http.StatusNotFound {
				t.Errorf("%s %s: code=%d", rt.method, rt.path, rec.Code)
			}
		}
	}
}

func TestAddEntry(t *testing.T) {
	f := newWriteFixture(t)
	f.seed(t, []domain.Tracker{weightTracker("tr-w", "Weight"), medTracker("tr-med"), paused(medTracker("tr-paused"))}, nil)

	// Absent at is now: logged ad hoc, by a caregiver who is not an admin.
	rec := f.do("cg", http.MethodPost, "/v1/trackers/tr-w/entries", `{"values":{"w":150},"note":"after lunch"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("ad hoc: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[entryDetail](t, rec)
	if d.Entry.State != "logged" || d.Entry.At != ts(trackerNow) || d.Entry.ByName != "Cal" ||
		d.Planned || d.Entry.Note != "after lunch" || d.SettledAt == nil || d.Entry.EntryID != "new-1" {
		t.Fatalf("ad hoc: %+v", d)
	}
	// An earlier time is logged at that time.
	past := trackerNow.Add(-3 * time.Hour)
	rec = f.do("cg", http.MethodPost, "/v1/trackers/tr-w/entries", fmt.Sprintf(`{"at":%q,"values":{"w":151}}`, ts(past)))
	if d := decode[entryDetail](t, rec); rec.Code != http.StatusCreated || d.Entry.At != ts(past) || d.Entry.State != "logged" {
		t.Fatalf("past: %d %+v", rec.Code, d)
	}
	// A future time plans: values pre-fill, a reading may be blank, and the
	// alert choice is kept.
	soon := trackerNow.Add(2 * time.Hour)
	rec = f.do("cg", http.MethodPost, "/v1/trackers/tr-w/entries", fmt.Sprintf(`{"at":%q,"values":{},"unrecorded_alert":true}`, ts(soon)))
	if rec.Code != http.StatusCreated {
		t.Fatalf("plan: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d = decode[entryDetail](t, rec)
	if d.Entry.State != "scheduled" || !d.Planned || d.OccurrenceAt == nil || *d.OccurrenceAt != ts(soon) ||
		d.UnrecordedAlert == nil || !*d.UnrecordedAlert || d.Entry.ByName != "" || d.Entry.ScheduleID != "" {
		t.Fatalf("plan: %+v", d)
	}
	planID := d.Entry.EntryID
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r1/coming-up", "")
	if got := receiverEntryIDs(decode[[]receiverEntry](t, rec)); got != "[tr-w/"+planID+":scheduled]" {
		t.Fatalf("coming up after planning: %s", got)
	}
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r1/waiting", "")
	if got := receiverEntryIDs(decode[[]receiverEntry](t, rec)); got != "[tr-w/"+planID+":scheduled]" {
		t.Fatalf("waiting after planning: %s", got)
	}

	for name, tc := range map[string]struct {
		tracker, body string
		code          int
	}{
		"required missing on a log":   {"tr-w", `{"values":{}}`, http.StatusBadRequest},
		"alert on a log":              {"tr-w", `{"values":{"w":1},"unrecorded_alert":true}`, http.StatusBadRequest},
		"values left out":             {"tr-w", `{}`, http.StatusBadRequest},
		"wrong kind":                  {"tr-w", `{"values":{"w":"heavy"}}`, http.StatusBadRequest},
		"paused field":                {"tr-med", `{"values":{"old-field":"x"}}`, http.StatusBadRequest},
		"retired option":              {"tr-med", `{"values":{"pills":["old"]}}`, http.StatusBadRequest},
		"two answers to one":          {"tr-w", `{"values":{"w":[1,2]}}`, http.StatusBadRequest},
		"long note":                   {"tr-w", `{"values":{"w":1},"note":"` + strings.Repeat("x", 2001) + `"}`, http.StatusBadRequest},
		"not json":                    {"tr-w", `nope`, http.StatusBadRequest},
		"paused tracker":              {"tr-paused", `{"values":{}}`, http.StatusConflict},
		"paused tracker, even future": {"tr-paused", fmt.Sprintf(`{"at":%q,"values":{}}`, ts(soon)), http.StatusConflict},
	} {
		if rec := f.do("cg", http.MethodPost, "/v1/trackers/"+tc.tracker+"/entries", tc.body); rec.Code != tc.code {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
}

func TestLogEntry(t *testing.T) {
	f := newWriteFixture(t)
	occ := trackerNow.Add(-2 * time.Hour)
	f.seed(t, []domain.Tracker{medTracker("tr1"), paused(medTracker("tr-paused"))}, []domain.Entry{
		planned("due", "tr1", occ), planned("race", "tr1", occ.Add(time.Minute)),
		planned("ahead", "tr1", trackerNow.Add(3*time.Hour)), planned("p", "tr-paused", occ),
		logged("ad", "tr1", "admin", occ, nil),
	})
	ran := trackerNow.Add(-30 * time.Minute)

	// The run's time is what the entry records, not the occurrence's.
	rec := f.do("cg", http.MethodPost, "/v1/entries/due/log", careBody(ran, `{"dose":10,"pills":["a","b"]}`, "late"))
	if rec.Code != http.StatusOK {
		t.Fatalf("log: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[entryDetail](t, rec)
	if d.Entry.State != "logged" || d.Entry.At != ts(ran) || *d.OccurrenceAt != ts(occ) || d.Entry.ByName != "Cal" ||
		d.Entry.Values["dose"] != 10.0 || d.Entry.Note != "late" || d.SettledAt == nil || *d.SettledAt != ts(trackerNow) ||
		d.UpdatedByName != "" {
		t.Fatalf("logged: %+v", d)
	}
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r1/waiting", "")
	if got := receiverEntryIDs(decode[[]receiverEntry](t, rec)); got != "[tr1/race:unrecorded tr1/ahead:scheduled]" {
		t.Fatalf("waiting after log: %s", got)
	}
	// Logged already: settled first by somebody.
	if rec := f.do("admin", http.MethodPost, "/v1/entries/due/log", careBody(ran, `{}`, "")); rec.Code != http.StatusConflict {
		t.Fatalf("log twice: code=%d", rec.Code)
	}
	// Two caregivers logging the same occurrence at once: exactly one wins.
	codes := make([]int, 2)
	var wg sync.WaitGroup
	for i, who := range []string{"admin", "cg"} {
		wg.Add(1)
		go func(i int, who string) {
			defer wg.Done()
			codes[i] = f.do(who, http.MethodPost, "/v1/entries/race/log", careBody(ran, `{}`, "")).Code
		}(i, who)
	}
	wg.Wait()
	if !(codes[0] == http.StatusOK && codes[1] == http.StatusConflict || codes[0] == http.StatusConflict && codes[1] == http.StatusOK) {
		t.Fatalf("concurrent logs: %v", codes)
	}

	for name, tc := range map[string]struct {
		entry, body string
		code        int
	}{
		"future occurred_at":   {"ahead", careBody(trackerNow.Add(2*time.Minute), `{}`, ""), http.StatusBadRequest},
		"occurred_at left out": {"ahead", `{"values":{}}`, http.StatusBadRequest},
		"paused field":         {"ahead", careBody(ran, `{"old-field":"x"}`, ""), http.StatusBadRequest},
		"paused tracker":       {"p", careBody(ran, `{}`, ""), http.StatusConflict},
		"ad hoc":               {"ad", careBody(ran, `{}`, ""), http.StatusConflict},
	} {
		if rec := f.do("cg", http.MethodPost, "/v1/entries/"+tc.entry+"/log", tc.body); rec.Code != tc.code {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
	// Within the clock skew is now; an occurrence still ahead can be logged.
	rec = f.do("cg", http.MethodPost, "/v1/entries/ahead/log", careBody(trackerNow.Add(30*time.Second), `{}`, ""))
	if d := decode[entryDetail](t, rec); rec.Code != http.StatusOK || d.Entry.At != ts(trackerNow) {
		t.Fatalf("skewed log: %d %+v", rec.Code, d)
	}
}

func TestSkipEntry(t *testing.T) {
	f := newWriteFixture(t)
	ahead := trackerNow.Add(3 * time.Hour)
	f.seed(t, []domain.Tracker{medTracker("tr1"), paused(medTracker("tr-paused"))}, []domain.Entry{
		planned("ahead", "tr1", ahead), planned("past", "tr1", trackerNow.Add(-time.Hour)),
		planned("p", "tr-paused", ahead), logged("ad", "tr1", "admin", trackerNow.Add(-time.Hour), nil),
	})
	// Still ahead: skipping is a decision whatever the hour.
	rec := f.do("cg", http.MethodPost, "/v1/entries/ahead/skip", `{"note":"at the doctor's"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("skip: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[entryDetail](t, rec)
	if d.Entry.State != "skipped" || d.Entry.At != ts(ahead) || d.Entry.ByName != "Cal" || d.Entry.Note != "at the doctor's" ||
		*d.SettledAt != ts(trackerNow) || d.Entry.Values["dose"] != 5.0 {
		t.Fatalf("skipped: %+v", d)
	}
	// No body is no note.
	if rec := f.do("cg", http.MethodPost, "/v1/entries/past/skip", ""); rec.Code != http.StatusOK {
		t.Fatalf("skip without body: code=%d body=%s", rec.Code, rec.Body.String())
	}
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r1/coming-up", "")
	if got := receiverEntryIDs(decode[[]receiverEntry](t, rec)); got != "[]" {
		t.Fatalf("coming up after skip: %s", got)
	}
	for name, tc := range map[string]struct {
		entry, body string
		code        int
	}{
		"skipped already": {"ahead", `{}`, http.StatusConflict},
		"ad hoc":          {"ad", `{}`, http.StatusConflict},
		"paused tracker":  {"p", `{}`, http.StatusConflict},
	} {
		if rec := f.do("cg", http.MethodPost, "/v1/entries/"+tc.entry+"/skip", tc.body); rec.Code != tc.code {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
	f.seed(t, nil, []domain.Entry{planned("fresh", "tr1", ahead.Add(time.Hour))})
	if rec := f.do("cg", http.MethodPost, "/v1/entries/fresh/skip", `{"note":"`+strings.Repeat("x", 2001)+`"}`); rec.Code != http.StatusBadRequest {
		t.Errorf("long note: code=%d", rec.Code)
	}
}

func TestChangeEntry(t *testing.T) {
	f := newWriteFixture(t)
	occ := trackerNow.Add(-2 * time.Hour)
	sk := planned("sk", "tr1", occ)
	sk.State, sk.OpenAt, sk.SkippedBy, sk.SkippedAt = domain.EntrySkipped, nil, "admin", &occ
	old := logged("old", "tr1", "admin", occ, map[string]any{"dose": 5.0, "old-field": "kept", "pills": []any{"old"}})
	w := weightTracker("tr-w", "Weight")
	w.Fields = append(w.Fields, domain.Field{FieldID: "bmi", Label: "BMI", Type: domain.FieldNumber, Required: true, Status: domain.FieldActive})
	// Skipped entries holding a value for a field paused since, one on a
	// tracker since paused, and one missing a required answer.
	skHeld := settledPlanned("sk-held", "tr1", "s1", occ, domain.EntrySkipped)
	skHeld.Values["old-field"] = "kept"
	skPaused := settledPlanned("sk-paused", "tr-paused", "s1", occ, domain.EntrySkipped)
	skPaused.Values = map[string]any{"w": 150.0}
	skW := settledPlanned("sk-w", "tr-w", "s1", occ, domain.EntrySkipped)
	skW.Values = map[string]any{"w": 150.0}
	f.seed(t, []domain.Tracker{medTracker("tr1"), w, paused(weightTracker("tr-paused", "Paused"))}, []domain.Entry{
		sk, old, planned("open", "tr1", occ), skHeld, skPaused, skW,
		logged("w1", "tr-w", "admin", occ, map[string]any{"w": 150.0}),
		logged("pz", "tr-paused", "admin", occ, map[string]any{"w": 150.0}),
	})
	fixed := trackerNow.Add(-26 * time.Hour)

	// Editing a skipped entry logs it, with the caller as who logged it.
	rec := f.do("cg", http.MethodPut, "/v1/entries/sk", careBody(occ.Add(time.Hour), `{"dose":5}`, "given after all"))
	if rec.Code != http.StatusOK {
		t.Fatalf("skipped → logged: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[entryDetail](t, rec)
	if d.Entry.State != "logged" || d.Entry.ByName != "Cal" || d.UpdatedByName != "Cal" || *d.UpdatedAt != ts(trackerNow) ||
		*d.SettledAt != ts(trackerNow) || d.Entry.At != ts(occ.Add(time.Hour)) || !d.Planned {
		t.Fatalf("skipped → logged: %+v", d)
	}
	// A logged entry keeps who logged it; a value for a field since paused,
	// and an option since retired, may stay. Moving it to another day moves
	// its timeline position.
	rec = f.do("cg", http.MethodPut, "/v1/entries/old", careBody(fixed, `{"dose":6,"old-field":"changed","pills":["old","a"]}`, ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("edit: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d = decode[entryDetail](t, rec)
	if d.Entry.ByName != "Ann" || d.UpdatedByName != "Cal" || d.Entry.At != ts(fixed) || d.Entry.Values["old-field"] != "changed" {
		t.Fatalf("edit: %+v", d)
	}
	// A required field the entry never answered need not be added to fix
	// another; one it did answer must stay answered.
	if rec := f.do("cg", http.MethodPut, "/v1/entries/w1", careBody(occ, `{"w":151}`, "")); rec.Code != http.StatusOK {
		t.Fatalf("edit without the new required field: code=%d body=%s", rec.Code, rec.Body.String())
	}
	// An entry on a paused tracker can still be corrected, but a skipped one
	// there cannot be logged by editing it, as it could not be logged at all.
	if rec := f.do("cg", http.MethodPut, "/v1/entries/pz", careBody(occ, `{"w":152}`, "")); rec.Code != http.StatusOK {
		t.Fatalf("edit on paused tracker: code=%d body=%s", rec.Code, rec.Body.String())
	}
	rec = f.do("cg", http.MethodPut, "/v1/entries/sk-paused", careBody(occ, `{"w":152}`, ""))
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), msgTrackerPaused) {
		t.Fatalf("skipped → logged on paused tracker: code=%d body=%s", rec.Code, rec.Body.String())
	}
	// A skipped entry may keep a value it already holds for a field paused
	// since, as a logged one may.
	rec = f.do("cg", http.MethodPut, "/v1/entries/sk-held", careBody(occ, `{"dose":5,"old-field":"kept"}`, ""))
	if rec.Code != http.StatusOK || decode[entryDetail](t, rec).Entry.Values["old-field"] != "kept" {
		t.Fatalf("skipped keeping a paused field: code=%d body=%s", rec.Code, rec.Body.String())
	}
	for name, tc := range map[string]struct {
		entry, body string
		code        int
	}{
		"scheduled":                   {"open", careBody(occ, `{}`, ""), http.StatusConflict},
		"clearing a required answer":  {"w1", careBody(occ, `{}`, ""), http.StatusBadRequest},
		"an unknown field":            {"w1", careBody(occ, `{"w":1,"zzz":1}`, ""), http.StatusBadRequest},
		"future":                      {"w1", careBody(trackerNow.Add(time.Hour), `{"w":1}`, ""), http.StatusBadRequest},
		"a paused field it never had": {"sk", careBody(occ, `{"old-field":"x"}`, ""), http.StatusBadRequest},
		"logging a skip unanswered":   {"sk-w", careBody(occ, `{"w":150}`, ""), http.StatusBadRequest},
	} {
		if rec := f.do("cg", http.MethodPut, "/v1/entries/"+tc.entry, tc.body); rec.Code != tc.code {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
	// A retired option the entry did not already hold is refused.
	f.seed(t, nil, []domain.Entry{logged("fresh", "tr1", "admin", occ, map[string]any{"dose": 1.0})})
	if rec := f.do("cg", http.MethodPut, "/v1/entries/fresh", careBody(occ, `{"pills":["old"]}`, "")); rec.Code != http.StatusBadRequest {
		t.Fatalf("retired option not held: code=%d", rec.Code)
	}
}

func TestDeleteEntry(t *testing.T) {
	f := newWriteFixture(t)
	occ := trackerNow.Add(-2 * time.Hour)
	f.put(t, f.l.Names.Schedules, liveSchedule("s1", "tr1"))
	f.seed(t, []domain.Tracker{medTracker("tr1")}, []domain.Entry{
		planned("p", "tr1", occ), planned("ahead", "tr1", trackerNow.Add(time.Hour)),
		logged("ad", "tr1", "admin", occ, nil), planned("open", "tr1", occ.Add(time.Minute)),
	})
	ran := trackerNow.Add(-10 * time.Minute)
	if rec := f.do("admin", http.MethodPost, "/v1/entries/p/log", careBody(ran, `{"dose":20,"pills":["b"]}`, "x")); rec.Code != http.StatusOK {
		t.Fatalf("log: %d %s", rec.Code, rec.Body.String())
	}
	if rec := f.do("admin", http.MethodPost, "/v1/entries/ahead/skip", `{"note":"no"}`); rec.Code != http.StatusOK {
		t.Fatalf("skip: %d", rec.Code)
	}

	// Undoing the log leaves the occurrence waiting, unrecorded since its time
	// has passed, with what was planned for it back.
	rec := f.do("cg", http.MethodDelete, "/v1/entries/p", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("delete planned: code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[entryDetail](t, rec)
	if d.Entry.State != "unrecorded" || d.Entry.At != ts(occ) || d.Entry.ByName != "" || d.Entry.Note != "" || d.SettledAt != nil ||
		!reflect.DeepEqual(d.Entry.Values, map[string]any{"dose": 5.0, "pills": []any{"a"}}) || d.UpdatedByName != "Cal" {
		t.Fatalf("reopened: %+v", d)
	}
	// Deleting a skip returns it to scheduled.
	rec = f.do("cg", http.MethodDelete, "/v1/entries/ahead", "")
	if d := decode[entryDetail](t, rec); rec.Code != http.StatusOK || d.Entry.State != "scheduled" || d.Entry.Note != "" {
		t.Fatalf("delete skip: %d %+v", rec.Code, d)
	}
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r1/waiting", "")
	if got := receiverEntryIDs(decode[[]receiverEntry](t, rec)); got != "[tr1/p:unrecorded tr1/open:unrecorded tr1/ahead:scheduled]" {
		t.Fatalf("waiting after delete: %s", got)
	}
	// It can be logged again.
	if rec := f.do("cg", http.MethodPost, "/v1/entries/p/log", careBody(ran, `{}`, "")); rec.Code != http.StatusOK {
		t.Fatalf("log after reopen: %d", rec.Code)
	}

	// An ad hoc entry is simply gone.
	if rec := f.do("cg", http.MethodDelete, "/v1/entries/ad", ""); rec.Code != http.StatusNoContent {
		t.Fatalf("delete ad hoc: code=%d body=%s", rec.Code, rec.Body.String())
	}
	if rec := f.do("cg", http.MethodGet, "/v1/entries/ad", ""); rec.Code != http.StatusNotFound {
		t.Fatalf("ad hoc after delete: %d", rec.Code)
	}
	// Waiting care cannot be deleted.
	if rec := f.do("cg", http.MethodDelete, "/v1/entries/open", ""); rec.Code != http.StatusConflict {
		t.Fatalf("delete waiting: %d", rec.Code)
	}
}

// settledPlanned is planned, already logged or skipped by admin.
func settledPlanned(id, tracker, schedule string, at time.Time, state domain.EntryState) domain.Entry {
	e := planned(id, tracker, at)
	e.ScheduleID, e.State, e.OpenAt = schedule, state, nil
	settled := at.Add(-time.Hour)
	if state == domain.EntryLogged {
		e.OccurredAt, e.LoggedBy, e.LoggedAt = &settled, "admin", &settled
		e.TimelineAt = settled
	} else {
		e.SkippedBy, e.SkippedAt = "admin", &settled
	}
	return e
}

func liveSchedule(id, tracker string) domain.Schedule {
	return domain.Schedule{ScheduleID: id, TrackerID: tracker, ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "08:00", StartsOn: "2026-11-01",
		CreatedBy: "admin", CreatedAt: trackerNow.Add(-48 * time.Hour), UpdatedAt: trackerNow.Add(-48 * time.Hour)}
}

// Deleting the log or skip of a planned entry leaves it waiting only if its
// plan still stands: a time still to come on a tracker since paused, or of a
// schedule since removed, leaves nothing; a time passed is unrecorded again.
func TestDeleteEntry_planGone(t *testing.T) {
	f := newWriteFixture(t)
	ahead, past := trackerNow.Add(3*time.Hour), trackerNow.Add(-3*time.Hour)
	removedAt := trackerNow.Add(-time.Hour)
	gone := liveSchedule("s-gone", "tr1")
	gone.RemovedAt = &removedAt
	f.put(t, f.l.Names.Schedules, liveSchedule("s1", "tr1"))
	f.put(t, f.l.Names.Schedules, gone)
	f.put(t, f.l.Names.Schedules, liveSchedule("s-p", "tr-p"))
	f.seed(t, []domain.Tracker{medTracker("tr1"), paused(medTracker("tr-p"))}, []domain.Entry{
		settledPlanned("paused-ahead", "tr-p", "s-p", ahead, domain.EntryLogged),
		settledPlanned("paused-past", "tr-p", "s-p", past, domain.EntryLogged),
		settledPlanned("removed-ahead", "tr1", "s-gone", ahead, domain.EntrySkipped),
		settledPlanned("removed-past", "tr1", "s-gone", past, domain.EntryLogged),
		settledPlanned("live-ahead", "tr1", "s1", ahead, domain.EntryLogged),
		settledPlanned("by-hand-ahead", "tr1", "", ahead, domain.EntrySkipped),
	})
	for id, want := range map[string]string{
		"paused-ahead": "", "paused-past": "unrecorded",
		"removed-ahead": "", "removed-past": "unrecorded",
		"live-ahead": "scheduled", "by-hand-ahead": "scheduled",
	} {
		rec := f.do("cg", http.MethodDelete, "/v1/entries/"+id, "")
		if want == "" {
			if rec.Code != http.StatusNoContent {
				t.Errorf("%s: code=%d body=%s, want 204", id, rec.Code, rec.Body.String())
			}
			if rec := f.do("cg", http.MethodGet, "/v1/entries/"+id, ""); rec.Code != http.StatusNotFound {
				t.Errorf("%s after delete: code=%d, want 404", id, rec.Code)
			}
			continue
		}
		if rec.Code != http.StatusOK {
			t.Errorf("%s: code=%d body=%s, want 200", id, rec.Code, rec.Body.String())
			continue
		}
		if d := decode[entryDetail](t, rec); d.Entry.State != want {
			t.Errorf("%s: state %s, want %s", id, d.Entry.State, want)
		}
	}
}

func TestJournalNoteWrites(t *testing.T) {
	f := newWriteFixture(t)
	about := trackerNow.Add(-26 * time.Hour)
	rec := f.do("cg", http.MethodPost, "/v1/receivers/r1/journal-notes", fmt.Sprintf(`{"at":%q,"body":"rough morning"}`, ts(about)))
	if rec.Code != http.StatusCreated {
		t.Fatalf("add: code=%d body=%s", rec.Code, rec.Body.String())
	}
	n := decode[journalNoteView](t, rec)
	if n.NoteID != "new-1" || n.At != ts(about) || n.AuthorName != "Cal" || n.Body != "rough morning" || n.UpdatedByName != "" ||
		n.CreatedAt != ts(trackerNow) || n.ReceiverID != "r1" {
		t.Fatalf("added: %+v", n)
	}
	rec = f.do("admin", http.MethodGet, "/v1/receivers/r1/timeline?date=2026-11-07", "")
	if day := decode[dayTimeline](t, rec); len(day.Items) != 1 || day.Items[0].Note == nil || day.Items[0].Note.NoteID != "new-1" {
		t.Fatalf("timeline: %+v", day)
	}

	// Anyone edits; the author stays and the editor is recorded.
	rec = f.do("admin", http.MethodPut, "/v1/journal-notes/new-1", fmt.Sprintf(`{"at":%q,"body":"rough morning, better by noon"}`, ts(about)))
	if rec.Code != http.StatusOK {
		t.Fatalf("change: code=%d body=%s", rec.Code, rec.Body.String())
	}
	n = decode[journalNoteView](t, rec)
	if n.AuthorName != "Cal" || n.UpdatedByName != "Ann" || *n.UpdatedAt != ts(trackerNow) || n.Body != "rough morning, better by noon" {
		t.Fatalf("changed: %+v", n)
	}

	for name, body := range map[string]string{
		"future":    fmt.Sprintf(`{"at":%q,"body":"x"}`, ts(trackerNow.Add(time.Hour))),
		"blank":     fmt.Sprintf(`{"at":%q,"body":"  "}`, ts(about)),
		"no at":     `{"body":"x"}`,
		"too long":  fmt.Sprintf(`{"at":%q,"body":%q}`, ts(about), strings.Repeat("x", 5001)),
		"not json":  `x`,
		"null body": fmt.Sprintf(`{"at":%q,"body":null}`, ts(about)),
	} {
		if rec := f.do("cg", http.MethodPost, "/v1/receivers/r1/journal-notes", body); rec.Code != http.StatusBadRequest {
			t.Errorf("add %s: code=%d", name, rec.Code)
		}
		if rec := f.do("cg", http.MethodPut, "/v1/journal-notes/new-1", body); rec.Code != http.StatusBadRequest {
			t.Errorf("change %s: code=%d", name, rec.Code)
		}
	}

	if rec := f.do("admin", http.MethodDelete, "/v1/journal-notes/new-1", ""); rec.Code != http.StatusNoContent {
		t.Fatalf("delete: code=%d", rec.Code)
	}
	if rec := f.do("admin", http.MethodGet, "/v1/journal-notes/new-1", ""); rec.Code != http.StatusNotFound {
		t.Fatalf("after delete: code=%d", rec.Code)
	}
	if rec := f.do("admin", http.MethodDelete, "/v1/journal-notes/new-1", ""); rec.Code != http.StatusNotFound {
		t.Fatalf("delete twice: code=%d", rec.Code)
	}
}
