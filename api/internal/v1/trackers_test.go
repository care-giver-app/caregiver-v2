package v1

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

// trackerNow is noon in Chicago (CST, UTC-6, after DST ended on 1 November).
var trackerNow = time.Date(2026, 11, 8, 18, 0, 0, 0, time.UTC)

// trackerFixture is one team (admin "admin", caregiver "cg") with an active
// receiver in Chicago and an archived one, plus an outsider on another team.
type trackerFixture struct {
	l   dynamotest.Local
	mux *http.ServeMux
	ids int
}

func newTrackerFixture(t *testing.T) *trackerFixture {
	t.Helper()
	l := dynamotest.StartLocal(t)
	f := &trackerFixture{l: l}
	created := trackerNow.Add(-30 * 24 * time.Hour)
	seedUser(t, l.Stores, domain.User{UserID: "admin", Email: "a@x.com", Name: "Ann", CreatedAt: created})
	seedUser(t, l.Stores, domain.User{UserID: "cg", Email: "c@x.com", Name: "Cal", CreatedAt: created})
	seedUser(t, l.Stores, domain.User{UserID: "out", Email: "o@x.com", Name: "Oz", CreatedAt: created})
	seedUser(t, l.Stores, domain.User{UserID: "gone", Name: "", Status: domain.UserClosed, CreatedAt: created})
	seedTeam(t, l.Stores, "t1", "The Smiths", "admin", domain.TeamActive, created)
	seedTeam(t, l.Stores, "t2", "Elsewhere", "out", domain.TeamActive, created)
	seedTeam(t, l.Stores, "t-closed", "Closed", "admin", domain.TeamArchived, created)
	f.put(t, l.Names.Memberships, domain.NewMembership("cg", "t1", domain.RoleCaregiver, created))
	for _, rc := range []domain.Receiver{
		{ReceiverID: "r1", TeamID: "t1", Name: "Grandma", TimeZone: "America/Chicago", Status: domain.ReceiverActive, CreatedAt: created},
		{ReceiverID: "r0", TeamID: "t1", Name: "Grandpa", TimeZone: "America/Chicago", Status: domain.ReceiverActive, CreatedAt: created.Add(-time.Hour)},
		{ReceiverID: "r-arch", TeamID: "t1", Name: "Gone", TimeZone: "America/Chicago", Status: domain.ReceiverArchived, CreatedAt: created},
		{ReceiverID: "r2", TeamID: "t2", Name: "Other", TimeZone: "UTC", Status: domain.ReceiverActive, CreatedAt: created},
	} {
		rc.CreatedBy = "admin"
		f.put(t, l.Names.Receivers, rc)
	}

	h := NewTrackers(l.Stores)
	h.now = func() time.Time { return trackerNow }
	h.newID = func() string { f.ids++; return fmt.Sprintf("new-%d", f.ids) }
	rcv := NewReceivers(l.Stores)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/teams/{teamId}/receivers", rcv.ListByTeam)
	mux.HandleFunc("GET /v1/receivers/{receiverId}/trackers", h.ListByReceiver)
	mux.HandleFunc("POST /v1/receivers/{receiverId}/trackers", h.Create)
	mux.HandleFunc("GET /v1/trackers/{trackerId}", h.Get)
	mux.HandleFunc("PUT /v1/trackers/{trackerId}", h.Edit)
	mux.HandleFunc("POST /v1/trackers/{trackerId}/pause", h.Pause)
	mux.HandleFunc("POST /v1/trackers/{trackerId}/resume", h.Resume)
	mux.HandleFunc("GET /v1/trackers/{trackerId}/entries", h.Entries)
	mux.HandleFunc("GET /v1/trackers/{trackerId}/schedules", h.Schedules)
	mux.HandleFunc("GET /v1/tracker-templates", NewTemplates().List)
	f.mux = mux
	return f
}

// put writes v as a raw row, for entities no store method writes.
func (f *trackerFixture) put(t *testing.T, table string, v any) {
	t.Helper()
	item, err := store.MarshalItem(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if _, err := f.l.Client.PutItem(context.Background(), &dynamodb.PutItemInput{TableName: aws.String(table), Item: item}); err != nil {
		t.Fatalf("put %s: %v", table, err)
	}
}

func (f *trackerFixture) do(as, method, path, body string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	f.mux.ServeHTTP(rec, asCaller(jsonRequest(method, path, body), as, as+"@x.com", as))
	return rec
}

func f64p(v float64) *float64 { return &v }
func intp(v int) *int         { return &v }

// weightTracker is a number tracker with a range, on r1.
func weightTracker(id, name string) domain.Tracker {
	return domain.Tracker{
		TrackerID: id, ReceiverID: "r1", TeamID: "t1", Name: name, Icon: "scalemass", Color: "#4F8EF7",
		Fields: []domain.Field{{FieldID: "w", Label: "Weight", Type: domain.FieldNumber, Unit: "lb", Required: true,
			Status: domain.FieldActive, Range: &domain.Range{Low: f64p(80), High: f64p(400)}}},
		Status: domain.TrackerActive, CreatedBy: "admin", CreatedAt: trackerNow.Add(-10 * 24 * time.Hour),
	}
}

func logged(id, tracker, by string, at time.Time, vals map[string]any) domain.Entry {
	if vals == nil {
		vals = map[string]any{}
	}
	return domain.Entry{
		EntryID: id, TrackerID: tracker, ReceiverID: "r1", TeamID: "t1", State: domain.EntryLogged, Values: vals,
		OccurredAt: &at, LoggedBy: by, LoggedAt: &at, CreatedBy: by, CreatedAt: at, TimelineAt: at,
	}
}

func scheduled(id, tracker, schedule string, at time.Time) domain.Entry {
	return domain.Entry{
		EntryID: id, TrackerID: tracker, ReceiverID: "r1", TeamID: "t1", State: domain.EntryScheduled,
		ScheduleID: schedule, OccurrenceAt: &at, Values: map[string]any{}, CreatedBy: "admin",
		CreatedAt: trackerNow.Add(-20 * 24 * time.Hour), TimelineAt: at, OpenAt: &at,
	}
}

func TestTrackers_authz(t *testing.T) {
	f := newTrackerFixture(t)
	f.put(t, f.l.Names.Trackers, weightTracker("tr1", "Weight"))
	arch := weightTracker("tr-arch", "Weight")
	arch.ReceiverID = "r-arch"
	f.put(t, f.l.Names.Trackers, arch)
	edit := `{"name":"Weight","icon":"scalemass","color":"#4F8EF7","gap_hours":null,"fields":[
		{"field_id":"w","label":"Weight","type":"number","unit":"lb","required":true,"range":{"low":80,"high":400}}]}`
	create := `{"name":"Walk","icon":"figure.walk","color":"#0EA5E9","fields":[]}`

	type route struct{ method, path, body string }
	reads := []route{
		{http.MethodGet, "/v1/receivers/r1/trackers", ""},
		{http.MethodGet, "/v1/trackers/tr1", ""},
		{http.MethodGet, "/v1/trackers/tr1/entries", ""},
		{http.MethodGet, "/v1/trackers/tr1/schedules", ""},
		{http.MethodGet, "/v1/teams/t1/receivers", ""},
	}
	writes := []route{
		{http.MethodPost, "/v1/receivers/r1/trackers", create},
		{http.MethodPut, "/v1/trackers/tr1", edit},
		{http.MethodPost, "/v1/trackers/tr1/pause", ""},
		{http.MethodPost, "/v1/trackers/tr1/resume", ""},
	}
	for _, rt := range append(append([]route{}, reads...), writes...) {
		if rec := f.do("out", rt.method, rt.path, rt.body); rec.Code != http.StatusForbidden {
			t.Errorf("non-member %s %s: code=%d", rt.method, rt.path, rec.Code)
		}
	}
	for _, rt := range reads {
		if rec := f.do("cg", rt.method, rt.path, rt.body); rec.Code != http.StatusOK {
			t.Errorf("caregiver %s %s: code=%d body=%s", rt.method, rt.path, rec.Code, rec.Body.String())
		}
	}
	for _, rt := range writes {
		if rec := f.do("cg", rt.method, rt.path, rt.body); rec.Code != http.StatusForbidden {
			t.Errorf("caregiver write %s %s: code=%d", rt.method, rt.path, rec.Code)
		}
	}
	for _, rt := range []route{
		{http.MethodGet, "/v1/teams/nope/receivers", ""},
		{http.MethodGet, "/v1/teams/t-closed/receivers", ""},
		{http.MethodGet, "/v1/receivers/nope/trackers", ""},
		{http.MethodGet, "/v1/receivers/r-arch/trackers", ""},
		{http.MethodPost, "/v1/receivers/r-arch/trackers", create},
		{http.MethodGet, "/v1/trackers/nope", ""},
		{http.MethodGet, "/v1/trackers/tr-arch", ""},
		{http.MethodPut, "/v1/trackers/tr-arch", edit},
		{http.MethodPost, "/v1/trackers/tr-arch/pause", ""},
		{http.MethodGet, "/v1/trackers/tr-arch/entries", ""},
		{http.MethodGet, "/v1/trackers/nope/schedules", ""},
	} {
		if rec := f.do("admin", rt.method, rt.path, rt.body); rec.Code != http.StatusNotFound {
			t.Errorf("unknown %s %s: code=%d", rt.method, rt.path, rec.Code)
		}
	}
	rec := httptest.NewRecorder()
	f.mux.ServeHTTP(rec, jsonRequest(http.MethodGet, "/v1/trackers/tr1", ""))
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("no caller: code=%d", rec.Code)
	}
}

func TestReceivers_ListByTeam(t *testing.T) {
	f := newTrackerFixture(t)
	rec := f.do("cg", http.MethodGet, "/v1/teams/t1/receivers", "")
	got := decode[[]careReceiver](t, rec)
	if rec.Code != http.StatusOK || len(got) != 2 || got[0].ReceiverID != "r0" || got[1].ReceiverID != "r1" ||
		got[1].TimeZone != "America/Chicago" || got[1].TeamID != "t1" || got[1].Name != "Grandma" {
		t.Fatalf("code=%d got=%+v", rec.Code, got)
	}
}

func TestTrackers_ListByReceiver(t *testing.T) {
	f := newTrackerFixture(t)
	pausedAt := trackerNow.Add(-24 * time.Hour)
	zinc := weightTracker("tr-zinc", "Zinc")
	zinc.Status, zinc.PausedAt, zinc.PausedBy = domain.TrackerPaused, &pausedAt, "admin"
	bp := weightTracker("tr-bp", "bp")
	bp.Fields = nil
	for _, tr := range []domain.Tracker{weightTracker("tr-w", "weight"), bp, weightTracker("tr-apple", "Apple"), zinc} {
		f.put(t, f.l.Names.Trackers, tr)
	}
	f.put(t, f.l.Names.Entries, logged("w-old", "tr-w", "admin", trackerNow.Add(-5*time.Hour), map[string]any{"w": 150.0}))
	f.put(t, f.l.Names.Entries, logged("w-new", "tr-w", "admin", trackerNow.Add(-2*time.Hour), map[string]any{"w": 500.0}))
	f.put(t, f.l.Names.Entries, scheduled("bp-open", "tr-bp", "", trackerNow.Add(-time.Hour)))
	f.put(t, f.l.Names.Entries, logged("z", "tr-zinc", "admin", trackerNow.Add(-3*24*time.Hour), map[string]any{"w": 900.0}))

	rec := f.do("cg", http.MethodGet, "/v1/receivers/r1/trackers", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	rows := decode[[]map[string]any](t, rec)
	var names []string
	for _, r := range rows {
		names = append(names, fmt.Sprintf("%s:%v", r["name"], r["needs_attention"]))
	}
	if fmt.Sprint(names) != "[Apple:false bp:true weight:true Zinc:false]" {
		t.Fatalf("rows = %v", names)
	}
	if _, ok := rows[0]["last_logged_at"]; ok {
		t.Errorf("never-logged row carries last_logged_at: %v", rows[0])
	}
	if rows[2]["last_logged_at"] != "2026-11-08T16:00:00Z" || rows[2]["status"] != "active" {
		t.Errorf("weight row: %v", rows[2])
	}
	if rows[3]["status"] != "paused" || rows[3]["paused_at"] != "2026-11-07T18:00:00Z" {
		t.Errorf("paused row: %v", rows[3])
	}
}

func TestTrackers_GetDetail(t *testing.T) {
	f := newTrackerFixture(t)
	tr := weightTracker("tr1", "Weight")
	f.put(t, f.l.Names.Trackers, tr)
	f.put(t, f.l.Names.Entries, logged("e1", "tr1", "admin", trackerNow.Add(-time.Hour), map[string]any{"w": 50.0}))
	f.put(t, f.l.Names.Schedules, domain.Schedule{ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "08:00", StartsOn: "2026-11-01",
		CreatedBy: "admin", CreatedAt: trackerNow.Add(-time.Hour)})

	rec := f.do("cg", http.MethodGet, "/v1/trackers/tr1", "")
	d := decode[map[string]any](t, rec)
	att, _ := d["attention"].([]any)
	if rec.Code != http.StatusOK || d["schedule_count"] != 1.0 || d["last_logged_at"] != "2026-11-08T17:00:00Z" ||
		len(att) != 1 || d["created_at"] != "2026-10-29T18:00:00Z" || d["team_id"] != "t1" {
		t.Fatalf("code=%d detail=%v", rec.Code, d)
	}
	if _, ok := d["gap_hours"]; ok {
		t.Errorf("gap_hours present without a gap: %v", d)
	}
	a := att[0].(map[string]any)
	if a["kind"] != "out_of_range" || a["entry_id"] != "e1" || a["field_id"] != "w" || a["value"] != 50.0 {
		t.Errorf("attention: %v", a)
	}
	fields := d["fields"].([]any)
	if fl := fields[0].(map[string]any); fl["field_id"] != "w" || fl["unit"] != "lb" || fl["range"].(map[string]any)["low"] != 80.0 {
		t.Errorf("field: %v", fl)
	}
}

func TestTrackers_Create(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	body := `{"name":"  Mood ","icon":"face.smiling","color":"#6f5fe0","gap_hours":48,"fields":[
		{"label":"Mood","type":"choice","required":true,"options":[{"label":"great"},{"label":"ok"}]},
		{"label":"Weight","type":"number","unit":"lb","required":false,"range":{"high":400}}]}`
	rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/trackers", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	d := decode[trackerDetail](t, rec)
	if d.TrackerID != "new-1" || d.Name != "Mood" || d.ReceiverID != "r1" || d.TeamID != "t1" || d.Status != "active" ||
		d.GapHours == nil || *d.GapHours != 48 || len(d.Fields) != 2 || d.ScheduleCount != 0 || len(d.Attention) != 0 {
		t.Fatalf("detail: %+v", d)
	}
	mood := d.Fields[0]
	if mood.FieldID == "" || mood.Multiple == nil || *mood.Multiple || len(mood.Options) != 2 || mood.Options[0].OptionID == "" {
		t.Fatalf("choice field: %+v", mood)
	}
	stored, err := f.l.Stores.Trackers.Get(ctx, "new-1")
	if err != nil || stored.CreatedBy != "admin" || !stored.CreatedAt.Equal(trackerNow) || stored.Fields[1].Range.High == nil {
		t.Fatalf("stored: %+v err=%v", stored, err)
	}

	for name, body := range map[string]string{
		"empty name":     `{"name":" ","icon":"x","color":"#000000","fields":[]}`,
		"no icon":        `{"name":"A","icon":"","color":"#000000","fields":[]}`,
		"bad color":      `{"name":"A","icon":"x","color":"6f5fe0","fields":[]}`,
		"gap zero":       `{"name":"A","icon":"x","color":"#000000","gap_hours":0,"fields":[]}`,
		"field id sent":  `{"name":"A","icon":"x","color":"#000000","fields":[{"field_id":"f","label":"L","type":"text","required":true}]}`,
		"bad field type": `{"name":"A","icon":"x","color":"#000000","fields":[{"label":"L","type":"blob","required":true}]}`,
		"unit on text":   `{"name":"A","icon":"x","color":"#000000","fields":[{"label":"L","type":"text","unit":"lb","required":true}]}`,
		"malformed":      `{"name":`,
	} {
		if rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/trackers", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
}

func TestTrackers_Edit(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	base := weightTracker("tr1", "Weight")
	base.Fields = append(base.Fields, domain.Field{FieldID: "c", Label: "Mood", Type: domain.FieldChoice, Status: domain.FieldActive,
		Options: []domain.ChoiceOption{{OptionID: "o1", Label: "Good", Status: domain.OptionActive}, {OptionID: "o2", Label: "Bad", Status: domain.OptionActive}}})
	f.put(t, f.l.Names.Trackers, base)

	weight := `{"field_id":"w","label":"Weight","type":"number","unit":"lb","required":true,"range":{"low":80,"high":400}}`
	mood := `{"field_id":"c","label":"Mood","type":"choice","required":false,"options":[{"option_id":"o1","label":"Good"},{"option_id":"o2","label":"Bad","status":"retired"}]}`
	edit := func(color, gap, fields string) string {
		return `{"name":"Body weight","icon":"scalemass","color":"` + color + `","gap_hours":` + gap + `,"fields":[` + fields + `]}`
	}
	put := func(body string) *httptest.ResponseRecorder { return f.do("admin", http.MethodPut, "/v1/trackers/tr1", body) }

	for name, body := range map[string]string{
		"omitted field":   edit("#4F8EF7", "null", weight),
		"dropped option":  edit("#4F8EF7", "null", weight+`,{"field_id":"c","label":"Mood","type":"choice","required":false,"options":[{"option_id":"o1","label":"Good"}]}`),
		"type change":     edit("#4F8EF7", "null", `{"field_id":"w","label":"Weight","type":"text","required":true},`+mood),
		"bad color":       edit("blue", "null", weight+","+mood),
		"gap omitted":     `{"name":"Body weight","icon":"scalemass","color":"#4F8EF7","fields":[` + weight + "," + mood + `]}`,
		"unknown option":  edit("#4F8EF7", "null", weight+`,{"field_id":"c","label":"Mood","type":"choice","required":false,"options":[{"option_id":"o1","label":"Good"},{"option_id":"o2","label":"Bad"},{"option_id":"zz","label":"Z"}]}`),
		"gap below one":   edit("#4F8EF7", "0", weight+","+mood),
		"name too long":   strings.Replace(edit("#4F8EF7", "null", weight+","+mood), "Body weight", strings.Repeat("x", 101), 1),
		"malformed field": edit("#4F8EF7", "null", `{"field_id":3}`),
	} {
		rec := put(body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code=%d body=%s", name, rec.Code, rec.Body.String())
		}
	}
	if rec := put(edit("#4F8EF7", "null", weight)); !strings.Contains(rec.Body.String(), "left out") {
		t.Errorf("omitted field message: %s", rec.Body.String())
	}

	// A valid save renames, retires an option, adds a field and turns a gap on.
	rec := put(edit("#123456", "24", weight+","+mood+`,{"label":"Note","type":"text","required":false}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("save: code=%d body=%s", rec.Code, rec.Body.String())
	}
	got, _ := f.l.Stores.Trackers.Get(ctx, "tr1")
	if got.Name != "Body weight" || got.Color != "#123456" || got.GapHours == nil || *got.GapHours != 24 || len(got.Fields) != 3 ||
		got.Fields[1].Options[1].Status != domain.OptionRetired || got.Fields[2].FieldID == "" || got.CreatedBy != "admin" {
		t.Fatalf("stored: %+v", got)
	}

	// A gap over live schedules is refused, with or without remove_schedules,
	// until the schedule writes land.
	f.put(t, f.l.Names.Schedules, domain.Schedule{ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "08:00", StartsOn: "2026-11-01",
		CreatedBy: "admin", CreatedAt: trackerNow})
	newField := `,{"field_id":"` + got.Fields[2].FieldID + `","label":"Note","type":"text","required":false}`
	all := weight + "," + mood + newField
	if rec := put(edit("#123456", "24", all)); rec.Code != http.StatusConflict {
		t.Errorf("gap over schedules: code=%d body=%s", rec.Code, rec.Body.String())
	}
	withFlag := strings.Replace(edit("#123456", "24", all), `"gap_hours"`, `"remove_schedules":true,"gap_hours"`, 1)
	if rec := put(withFlag); rec.Code != http.StatusConflict {
		t.Errorf("gap over schedules with remove_schedules: code=%d", rec.Code)
	}
	if rec := put(edit("#123456", "null", all)); rec.Code != http.StatusOK {
		t.Errorf("gap off: code=%d body=%s", rec.Code, rec.Body.String())
	}

	// Editing is allowed on a paused tracker, and keeps it paused.
	if rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/pause", ""); rec.Code != http.StatusOK {
		t.Fatalf("pause: %d", rec.Code)
	}
	rec = put(strings.Replace(edit("#123456", "null", all), "Body weight", "Weight (paused)", 1))
	if d := decode[trackerDetail](t, rec); rec.Code != http.StatusOK || d.Status != "paused" || d.Name != "Weight (paused)" || d.PausedAt == nil {
		t.Errorf("edit paused: code=%d %+v", rec.Code, d)
	}
}

func TestTrackers_PauseResume(t *testing.T) {
	f := newTrackerFixture(t)
	ctx := context.Background()
	f.put(t, f.l.Names.Trackers, weightTracker("tr1", "Weight"))
	f.put(t, f.l.Names.Entries, scheduled("future-1", "tr1", "s1", trackerNow.Add(time.Hour)))
	f.put(t, f.l.Names.Entries, scheduled("future-2", "tr1", "s1", trackerNow.Add(72*time.Hour)))
	f.put(t, f.l.Names.Entries, scheduled("unrecorded", "tr1", "s1", trackerNow.Add(-time.Hour)))
	f.put(t, f.l.Names.Entries, logged("logged", "tr1", "admin", trackerNow.Add(-2*time.Hour), nil))

	rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/pause", "")
	d := decode[trackerDetail](t, rec)
	if rec.Code != http.StatusOK || d.Status != "paused" || d.PausedAt == nil || *d.PausedAt != "2026-11-08T18:00:00Z" || len(d.Attention) != 0 {
		t.Fatalf("pause: code=%d %+v", rec.Code, d)
	}
	left, _, err := f.l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", trackerNow.Add(100*time.Hour), nil, 50, "")
	var ids []string
	for _, e := range left {
		ids = append(ids, e.EntryID)
	}
	if err != nil || fmt.Sprint(ids) != "[unrecorded logged]" {
		t.Fatalf("after pause: %v err=%v", ids, err)
	}

	// A repeat changes nothing, not even paused_at.
	h := NewTrackers(f.l.Stores)
	h.now = func() time.Time { return trackerNow.Add(time.Hour) }
	rec = httptest.NewRecorder()
	req := asCaller(jsonRequest(http.MethodPost, "/v1/trackers/tr1/pause", ""), "admin", "", "Ann")
	req.SetPathValue("trackerId", "tr1")
	h.Pause(rec, req)
	if d := decode[trackerDetail](t, rec); rec.Code != http.StatusOK || d.Status != "paused" || *d.PausedAt != "2026-11-08T18:00:00Z" {
		t.Fatalf("repeat pause: code=%d %+v", rec.Code, d)
	}

	for i := 0; i < 2; i++ {
		rec := f.do("admin", http.MethodPost, "/v1/trackers/tr1/resume", "")
		if d := decode[trackerDetail](t, rec); rec.Code != http.StatusOK || d.Status != "active" || d.PausedAt != nil {
			t.Fatalf("resume %d: code=%d %+v", i, rec.Code, d)
		}
	}
	if got, _ := f.l.Stores.Trackers.Get(ctx, "tr1"); got.PausedBy != "" || got.PausedAt != nil {
		t.Fatalf("resumed row: %+v", got)
	}
}

func TestTrackers_Entries(t *testing.T) {
	f := newTrackerFixture(t)
	f.put(t, f.l.Names.Trackers, weightTracker("tr1", "Weight"))
	f.put(t, f.l.Names.Schedules, domain.Schedule{ScheduleID: "s-derived", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO", "WE", "FR"}}, Time: "08:00", StartsOn: "2026-11-01",
		CreatedBy: "admin", CreatedAt: trackerNow.Add(-10 * 24 * time.Hour)})
	removed := trackerNow.Add(-time.Hour)
	f.put(t, f.l.Names.Schedules, domain.Schedule{ScheduleID: "s-label", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		Label: "Evening weigh-in", Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SU"}}, Time: "20:00",
		StartsOn: "2026-11-01", RemovedAt: &removed, CreatedBy: "admin", CreatedAt: trackerNow.Add(-10 * 24 * time.Hour)})

	// Chicago is UTC-6: 05:30Z on the 8th is 23:30 on the 7th; 06:30Z is 00:30 on the 8th.
	skipAt := trackerNow.Add(-3 * time.Hour)
	skipped := scheduled("skipped", "tr1", "s-label", trackerNow.Add(-4*time.Hour))
	skipped.State, skipped.OpenAt, skipped.SkippedBy, skipped.SkippedAt, skipped.Note = domain.EntrySkipped, nil, "cg", &skipAt, "asleep"
	for _, e := range []domain.Entry{
		scheduled("future", "tr1", "s-derived", trackerNow.Add(2*time.Hour)),
		scheduled("unrecorded", "tr1", "s-derived", trackerNow.Add(-time.Hour)),
		skipped,
		logged("by-ann", "tr1", "admin", time.Date(2026, 11, 8, 6, 30, 0, 0, time.UTC), map[string]any{"w": 150.0}),
		logged("late-7th", "tr1", "admin", time.Date(2026, 11, 8, 5, 30, 0, 0, time.UTC), nil),
		logged("by-closed", "tr1", "gone", time.Date(2026, 11, 7, 16, 0, 0, 0, time.UTC), nil),
		logged("by-missing", "tr1", "nobody", time.Date(2026, 11, 7, 6, 0, 0, 0, time.UTC), nil),
		logged("early-6th", "tr1", "admin", time.Date(2026, 11, 7, 5, 59, 0, 0, time.UTC), nil),
	} {
		f.put(t, f.l.Names.Entries, e)
	}
	list := func(query string) (entryPage, int) {
		rec := f.do("cg", http.MethodGet, "/v1/trackers/tr1/entries"+query, "")
		if rec.Code != http.StatusOK {
			return entryPage{}, rec.Code
		}
		return decode[entryPage](t, rec), rec.Code
	}
	ids := func(p entryPage) string {
		var s []string
		for _, e := range p.Entries {
			s = append(s, e.EntryID)
		}
		return fmt.Sprint(s)
	}

	p, _ := list("")
	if ids(p) != "[unrecorded skipped by-ann late-7th by-closed by-missing early-6th]" || p.NextCursor != "" {
		t.Fatalf("all: %s next=%q", ids(p), p.NextCursor)
	}
	un, sk, ann, closed, missing := p.Entries[0], p.Entries[1], p.Entries[2], p.Entries[4], p.Entries[5]
	if un.State != "unrecorded" || un.ByName != "" || un.ScheduleName != "Mon, Wed, Fri at 8:00 AM" || un.At != "2026-11-08T17:00:00Z" {
		t.Errorf("unrecorded: %+v", un)
	}
	if sk.State != "skipped" || sk.ByName != "Cal" || sk.ScheduleName != "Evening weigh-in" || sk.Note != "asleep" {
		t.Errorf("skipped (removed schedule still named): %+v", sk)
	}
	if ann.State != "logged" || ann.ByName != "Ann" || ann.Values["w"] != 150.0 || ann.ScheduleID != "" || ann.ScheduleName != "" {
		t.Errorf("logged: %+v", ann)
	}
	if closed.ByName != formerCaregiver || missing.ByName != formerCaregiver {
		t.Errorf("former caregivers: %q %q", closed.ByName, missing.ByName)
	}

	// The 7th in Chicago runs 06:00Z on the 7th to 05:59:59Z on the 8th.
	if p, _ := list("?from=2026-11-07&to=2026-11-07"); ids(p) != "[late-7th by-closed by-missing]" {
		t.Errorf("one local day: %s", ids(p))
	}
	if p, _ := list("?to=2026-11-07"); ids(p) != "[late-7th by-closed by-missing early-6th]" {
		t.Errorf("to only: %s", ids(p))
	}
	if p, _ := list("?from=2026-11-08&to=2026-11-30"); ids(p) != "[unrecorded skipped by-ann]" {
		t.Errorf("to in the future still excludes what is to come: %s", ids(p))
	}
	if p, code := list("?from=2026-11-20"); code != http.StatusOK || ids(p) != "[]" {
		t.Errorf("from in the future: %d %s", code, ids(p))
	}

	var paged []string
	cursor := ""
	for page := 0; ; page++ {
		if page > 10 {
			t.Fatal("cursor never ended")
		}
		q := "?limit=3"
		if cursor != "" {
			q += "&cursor=" + cursor
		}
		p, code := list(q)
		if code != http.StatusOK || len(p.Entries) > 3 {
			t.Fatalf("page %d: code=%d n=%d", page, code, len(p.Entries))
		}
		for _, e := range p.Entries {
			paged = append(paged, e.EntryID)
		}
		if p.NextCursor == "" {
			break
		}
		cursor = p.NextCursor
	}
	if fmt.Sprint(paged) != "[unrecorded skipped by-ann late-7th by-closed by-missing early-6th]" {
		t.Errorf("paged: %v", paged)
	}

	for _, q := range []string{"?limit=0", "?limit=101", "?limit=x", "?from=2026-13-01", "?to=11/07/2026",
		"?from=2026-11-08&to=2026-11-07", "?cursor=!!!", "?cursor=e30"} {
		if _, code := list(q); code != http.StatusBadRequest {
			t.Errorf("%s: code=%d", q, code)
		}
	}
}

func TestTrackers_Schedules(t *testing.T) {
	f := newTrackerFixture(t)
	f.put(t, f.l.Names.Trackers, weightTracker("tr1", "Weight"))
	removed := trackerNow
	for i, sc := range []domain.Schedule{
		{ScheduleID: "morning", Label: "Morning dose", Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}},
			Time: "08:00", PlannedValues: map[string]any{"w": 1.0}, UnrecordedAlert: true, EndsOn: "2026-12-31"},
		{ScheduleID: "biweekly", Rule: domain.Rule{Freq: "weekly", Interval: 2, ByDay: []string{"TH", "TU"}}, Time: "21:00"},
		{ScheduleID: "removed", Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "09:00", RemovedAt: &removed},
	} {
		sc.TrackerID, sc.ReceiverID, sc.TeamID, sc.StartsOn, sc.CreatedBy = "tr1", "r1", "t1", "2026-11-01", "admin"
		sc.CreatedAt = trackerNow.Add(time.Duration(i) * time.Minute)
		f.put(t, f.l.Names.Schedules, sc)
	}
	rec := f.do("cg", http.MethodGet, "/v1/trackers/tr1/schedules", "")
	got := decode[[]map[string]any](t, rec)
	if rec.Code != http.StatusOK || len(got) != 2 {
		t.Fatalf("code=%d got=%v", rec.Code, got)
	}
	if got[0]["name"] != "Morning dose" || got[0]["label"] != "Morning dose" || got[0]["ends_on"] != "2026-12-31" ||
		got[0]["unrecorded_alert"] != true || got[0]["planned_values"].(map[string]any)["w"] != 1.0 {
		t.Errorf("labelled: %v", got[0])
	}
	if _, ok := got[1]["label"]; ok || got[1]["name"] != "Every 2 weeks: Tue, Thu at 9:00 PM" ||
		got[1]["rule"].(map[string]any)["interval"] != 2.0 || got[1]["starts_on"] != "2026-11-01" {
		t.Errorf("derived: %v", got[1])
	}
}

func TestTemplates_List(t *testing.T) {
	f := newTrackerFixture(t)
	rec := f.do("out", http.MethodGet, "/v1/tracker-templates", "")
	got := decode[[]map[string]any](t, rec)
	var names []string
	for _, tp := range got {
		names = append(names, tp["name"].(string))
	}
	if rec.Code != http.StatusOK || fmt.Sprint(names) != "[Mood Shower Urination Bowel Movement Medication Walk Weight Doctor Appointment]" {
		t.Fatalf("code=%d names=%v", rec.Code, names)
	}
	shower := got[1]
	if fs := shower["fields"].([]any); len(fs) != 0 || shower["gap_hours"] != 72.0 {
		t.Errorf("shower: %v", shower)
	}
	for _, fl := range got[7]["fields"].([]any) {
		if _, ok := fl.(map[string]any)["field_id"]; ok {
			t.Errorf("template field carries an id: %v", fl)
		}
	}
}
