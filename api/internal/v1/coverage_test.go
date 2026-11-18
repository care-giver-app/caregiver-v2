package v1

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
)

// newCoverageFixture is the team fixture with the roster routes, and a
// receiver r-closed on the closed team. teamNow is Sunday 2026-11-08, noon in
// Chicago.
func newCoverageFixture(t *testing.T) *teamFixture {
	t.Helper()
	f := newTeamFixture(t)
	f.put(t, f.l.Names.Receivers, domain.Receiver{ReceiverID: "r-closed", TeamID: "t-closed", Name: "X", TimeZone: "UTC",
		Status: domain.ReceiverActive, CreatedBy: "admin", CreatedAt: teamNow})
	cov := NewCoverage(f.l.Stores)
	cov.now = func() time.Time { return teamNow }
	n := 0
	cov.newID = func() string { n++; return fmt.Sprintf("cov-%d", n) }
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/on-duty", cov.OnDuty)
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/assignments", cov.Assignments)
	f.mux.HandleFunc("POST /v1/receivers/{receiverId}/assignments", cov.AddAssignment)
	f.mux.HandleFunc("PUT /v1/assignments/{assignmentId}", cov.ChangeAssignment)
	f.mux.HandleFunc("DELETE /v1/assignments/{assignmentId}", cov.RemoveAssignment)
	f.mux.HandleFunc("GET /v1/receivers/{receiverId}/coverage-schedules", cov.CoverageSchedules)
	f.mux.HandleFunc("POST /v1/receivers/{receiverId}/coverage-schedules", cov.AddCoverageSchedule)
	f.mux.HandleFunc("PUT /v1/coverage-schedules/{coverageScheduleId}", cov.ChangeCoverageSchedule)
	f.mux.HandleFunc("DELETE /v1/coverage-schedules/{coverageScheduleId}", cov.RemoveCoverageSchedule)
	return f
}

func (f *teamFixture) assignments(t *testing.T, path string) []assignmentView {
	t.Helper()
	rec := f.do("cg", http.MethodGet, path, "")
	want(t, rec, http.StatusOK)
	return decode[[]assignmentView](t, rec)
}

func TestCoverage_access(t *testing.T) {
	f := newCoverageFixture(t)
	for _, path := range []string{"/v1/receivers/r1/on-duty", "/v1/receivers/r1/assignments", "/v1/receivers/r1/coverage-schedules"} {
		rec := f.do("cg", http.MethodGet, path, "")
		want(t, rec, http.StatusOK)
		if rec.Body.String() != "[]\n" && rec.Body.String() != "[]" {
			t.Fatalf("%s: %s", path, rec.Body.String())
		}
		want(t, f.do("cg", http.MethodGet, "/v1/receivers/r-arch"+path[len("/v1/receivers/r1"):], ""), http.StatusOK)
		want(t, f.do("out", http.MethodGet, path, ""), http.StatusForbidden)
		want(t, f.do("admin", http.MethodGet, "/v1/receivers/missing"+path[len("/v1/receivers/r1"):], ""), http.StatusNotFound)
		want(t, f.do("admin", http.MethodGet, "/v1/receivers/r-closed"+path[len("/v1/receivers/r1"):], ""), http.StatusNotFound)
	}
	body := `{"user_id":"cg","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T16:00"}`
	rule := `{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"08:00","end_time":"16:00"}`
	want(t, f.do("cg", http.MethodPost, "/v1/receivers/r1/assignments", body), http.StatusForbidden)
	want(t, f.do("cg", http.MethodPost, "/v1/receivers/r1/coverage-schedules", rule), http.StatusForbidden)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r-arch/assignments", body), http.StatusConflict)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r-arch/coverage-schedules", rule), http.StatusConflict)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r-closed/assignments", body), http.StatusNotFound)
	want(t, f.do("admin", http.MethodPut, "/v1/assignments/missing", body), http.StatusNotFound)
	want(t, f.do("admin", http.MethodDelete, "/v1/coverage-schedules/missing", ""), http.StatusNotFound)
}

func TestCoverage_assignmentsByHand(t *testing.T) {
	f := newCoverageFixture(t)
	add := func(body string) *assignmentView {
		rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/assignments", body)
		if rec.Code != http.StatusCreated {
			return nil
		}
		v := decode[assignmentView](t, rec)
		return &v
	}
	tue := add(`{"user_id":"cg","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T16:00"}`)
	if tue == nil || tue.CaregiverName != "cal" || tue.StartsAt != "2026-11-10T14:00:00Z" || tue.EndsAt != "2026-11-10T22:00:00Z" ||
		tue.StartsLocal != "2026-11-10T08:00" || tue.CoverageScheduleID != "" || tue.ReceiverID != "r1" {
		t.Fatalf("tuesday: %+v", tue)
	}
	// Under way now (11:00–13:00 today), and overlapping it.
	now := add(`{"user_id":"admin","starts_local":"2026-11-08T11:00","ends_local":"2026-11-08T13:00"}`)
	also := add(`{"user_id":"cg","starts_local":"2026-11-08T09:00","ends_local":"2026-11-09T09:00"}`)
	if now == nil || also == nil {
		t.Fatal("add under way")
	}

	for body, why := range map[string]string{
		`{"user_id":"out","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T16:00"}`: "not on the team",
		`{"user_id":"","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T16:00"}`:    "no one",
		`{"user_id":"cg","starts_local":"2026-11-10T16:00","ends_local":"2026-11-10T08:00"}`:  "ends before it starts",
		`{"user_id":"cg","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T08:00"}`:  "no time at all",
		`{"user_id":"cg","starts_local":"2026-11-08T08:00","ends_local":"2026-11-08T11:00"}`:  "ended already",
		`{"user_id":"cg","starts_local":"2026-11-10 08:00","ends_local":"2026-11-10T16:00"}`:  "bad format",
		`{"user_id":"cg","starts_local":"2026-11-10T08:00"}`:                                  "no end",
		`not json`: "not json",
	} {
		if add(body) != nil {
			t.Errorf("%s: accepted", why)
		}
		if rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/assignments", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code %d", why, rec.Code)
		}
	}

	onDuty := f.assignments(t, "/v1/receivers/r1/on-duty")
	if len(onDuty) != 2 || onDuty[0].AssignmentID != also.AssignmentID || onDuty[1].AssignmentID != now.AssignmentID ||
		onDuty[1].CaregiverName != "Ann" {
		t.Fatalf("on duty: %+v", onDuty)
	}
	ahead := f.assignments(t, "/v1/receivers/r1/assignments")
	if len(ahead) != 3 || ahead[2].AssignmentID != tue.AssignmentID {
		t.Fatalf("ahead: %+v", ahead)
	}

	// Hand Tuesday to the admin.
	rec := f.do("admin", http.MethodPut, "/v1/assignments/"+tue.AssignmentID,
		`{"user_id":"admin","starts_local":"2026-11-10T09:00","ends_local":"2026-11-10T17:00"}`)
	want(t, rec, http.StatusOK)
	if got := decode[assignmentView](t, rec); got.CaregiverName != "Ann" || got.StartsAt != "2026-11-10T15:00:00Z" {
		t.Fatalf("changed: %+v", got)
	}
	want(t, f.do("cg", http.MethodPut, "/v1/assignments/"+tue.AssignmentID, `{}`), http.StatusForbidden)
	want(t, f.do("admin", http.MethodPut, "/v1/assignments/"+tue.AssignmentID,
		`{"user_id":"out","starts_local":"2026-11-10T09:00","ends_local":"2026-11-10T17:00"}`), http.StatusBadRequest)

	// One that has ended cannot be changed or removed.
	ended := domain.Assignment{
		AssignmentID: "ended", ReceiverID: "r1", TeamID: "t1", UserID: "cg", StartsLocal: "2026-11-08T06:00", EndsLocal: "2026-11-08T08:00",
		StartsAt: teamNow.Add(-6 * time.Hour), EndsAt: teamNow.Add(-4 * time.Hour), Status: domain.AssignmentActive,
		CreatedBy: "admin", CreatedAt: teamNow.Add(-24 * time.Hour),
	}
	f.put(t, f.l.Names.Assignments, ended)
	want(t, f.do("admin", http.MethodPut, "/v1/assignments/ended",
		`{"user_id":"admin","starts_local":"2026-11-10T09:00","ends_local":"2026-11-10T17:00"}`), http.StatusConflict)
	want(t, f.do("admin", http.MethodDelete, "/v1/assignments/ended", ""), http.StatusConflict)

	// Removing one made by hand drops it.
	want(t, f.do("cg", http.MethodDelete, "/v1/assignments/"+tue.AssignmentID, ""), http.StatusForbidden)
	want(t, f.do("admin", http.MethodDelete, "/v1/assignments/"+tue.AssignmentID, ""), http.StatusNoContent)
	want(t, f.do("admin", http.MethodDelete, "/v1/assignments/"+tue.AssignmentID, ""), http.StatusNotFound)
	if ahead := f.assignments(t, "/v1/receivers/r1/assignments"); len(ahead) != 2 {
		t.Fatalf("after remove: %+v", ahead)
	}

	// An archived receiver's assignments are read-only.
	archived := ended
	archived.AssignmentID, archived.ReceiverID, archived.EndsAt = "arch", "r-arch", teamNow.Add(48*time.Hour)
	f.put(t, f.l.Names.Assignments, archived)
	want(t, f.do("admin", http.MethodDelete, "/v1/assignments/arch", ""), http.StatusConflict)
}

func TestCoverage_schedules(t *testing.T) {
	f := newCoverageFixture(t)
	ctx := context.Background()
	rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/coverage-schedules",
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"08:00","end_time":"16:00"}`)
	want(t, rec, http.StatusCreated)
	cs := decode[coverageScheduleView](t, rec)
	if cs.StartsOn != "2026-11-08" || cs.CaregiverName != "cal" || cs.EndsOn != "" || cs.Rule.ByDay[0] != "TU" {
		t.Fatalf("rule: %+v", cs)
	}
	id := cs.CoverageScheduleID
	ahead := f.assignments(t, "/v1/receivers/r1/assignments")
	if len(ahead) != 2 || ahead[0].StartsLocal != "2026-11-10T08:00" || ahead[0].CoverageScheduleID != id ||
		ahead[1].StartsLocal != "2026-11-17T08:00" {
		t.Fatalf("generated: %+v", ahead)
	}
	first, second := ahead[0], ahead[1]

	// Hand the first Tuesday to the admin: it belongs to no rule afterward.
	rec = f.do("admin", http.MethodPut, "/v1/assignments/"+first.AssignmentID,
		`{"user_id":"admin","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T16:00"}`)
	want(t, rec, http.StatusOK)
	if got := decode[assignmentView](t, rec); got.CoverageScheduleID != "" || got.CaregiverName != "Ann" {
		t.Fatalf("handed: %+v", got)
	}

	// Redraw the rule with a later start: the second Tuesday moves; the first
	// stays the admin's, with no second assignment beside it.
	rec = f.do("admin", http.MethodPut, "/v1/coverage-schedules/"+id,
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"17:00"}`)
	want(t, rec, http.StatusOK)
	ahead = f.assignments(t, "/v1/receivers/r1/assignments")
	if len(ahead) != 2 || ahead[0].AssignmentID != first.AssignmentID || ahead[0].StartsLocal != "2026-11-10T08:00" ||
		ahead[1].AssignmentID != second.AssignmentID || ahead[1].StartsLocal != "2026-11-17T09:00" || ahead[1].CoverageScheduleID != id {
		t.Fatalf("redrawn: %+v", ahead)
	}

	// Drop the second Tuesday; redrawing again does not bring it back.
	want(t, f.do("admin", http.MethodDelete, "/v1/assignments/"+second.AssignmentID, ""), http.StatusNoContent)
	want(t, f.do("admin", http.MethodPut, "/v1/coverage-schedules/"+id,
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"18:00"}`), http.StatusOK)
	if ahead = f.assignments(t, "/v1/receivers/r1/assignments"); len(ahead) != 1 || ahead[0].AssignmentID != first.AssignmentID {
		t.Fatalf("dropped: %+v", ahead)
	}

	// Bad saves.
	for body, why := range map[string]string{
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"09:00"}`:                        "equal times",
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"17:00","ends_on":"2026-11-07"}`: "ends in the past",
		`{"user_id":"out","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"17:00"}`:                       "not on the team",
		`{"user_id":"cg","rule":{"freq":"daily","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"17:00"}`:                         "daily",
		`{"user_id":"cg","start_time":"09:00","end_time":"17:00"}`:                                                                              "no rule",
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"9:00","end_time":"17:00"}`:                         "bad time",
	} {
		if rec := f.do("admin", http.MethodPut, "/v1/coverage-schedules/"+id, body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code %d", why, rec.Code)
		}
		if rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/coverage-schedules", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s (add): code %d", why, rec.Code)
		}
	}

	// Ending it today stops it from tomorrow.
	rec = f.do("admin", http.MethodPut, "/v1/coverage-schedules/"+id,
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU","WE"]},"start_time":"09:00","end_time":"17:00","ends_on":"2026-11-08"}`)
	want(t, rec, http.StatusOK)
	if got := decode[coverageScheduleView](t, rec); got.EndsOn != "2026-11-08" {
		t.Fatalf("ended: %+v", got)
	}
	if ahead = f.assignments(t, "/v1/receivers/r1/assignments"); len(ahead) != 1 {
		t.Fatalf("after ending: %+v", ahead)
	}
	rules := decode[[]coverageScheduleView](t, f.do("cg", http.MethodGet, "/v1/receivers/r1/coverage-schedules", ""))
	if len(rules) != 1 || rules[0].EndsOn != "2026-11-08" {
		t.Fatalf("ended rule still listed: %+v", rules)
	}

	// Remove it: past and hand-changed assignments stay; repeating is a 204.
	want(t, f.do("cg", http.MethodDelete, "/v1/coverage-schedules/"+id, ""), http.StatusForbidden)
	want(t, f.do("admin", http.MethodDelete, "/v1/coverage-schedules/"+id, ""), http.StatusNoContent)
	want(t, f.do("admin", http.MethodDelete, "/v1/coverage-schedules/"+id, ""), http.StatusNoContent)
	want(t, f.do("admin", http.MethodPut, "/v1/coverage-schedules/"+id,
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"09:00","end_time":"17:00"}`), http.StatusNotFound)
	if rules := decode[[]coverageScheduleView](t, f.do("cg", http.MethodGet, "/v1/receivers/r1/coverage-schedules", "")); len(rules) != 0 {
		t.Fatalf("removed rule listed: %+v", rules)
	}
	if ahead = f.assignments(t, "/v1/receivers/r1/assignments"); len(ahead) != 1 || ahead[0].AssignmentID != first.AssignmentID {
		t.Fatalf("after remove: %+v", ahead)
	}
	if got, _ := f.l.Stores.CoverageSchedules.Get(ctx, id); got.RemovedAt == nil {
		t.Fatalf("not marked removed: %+v", got)
	}
}

func TestCoverage_removingRuleKeepsWhatIsUnderWay(t *testing.T) {
	f := newCoverageFixture(t)
	// Sundays 10:00–14:00: today's is under way at noon.
	rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/coverage-schedules",
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["SU"]},"start_time":"10:00","end_time":"14:00"}`)
	want(t, rec, http.StatusCreated)
	id := decode[coverageScheduleView](t, rec).CoverageScheduleID
	onDuty := f.assignments(t, "/v1/receivers/r1/on-duty")
	if len(onDuty) != 1 || onDuty[0].StartsLocal != "2026-11-08T10:00" || onDuty[0].CoverageScheduleID != id {
		t.Fatalf("on duty: %+v", onDuty)
	}
	want(t, f.do("admin", http.MethodDelete, "/v1/coverage-schedules/"+id, ""), http.StatusNoContent)
	if ahead := f.assignments(t, "/v1/receivers/r1/assignments"); len(ahead) != 1 || ahead[0].StartsLocal != "2026-11-08T10:00" {
		t.Fatalf("after remove: %+v", ahead)
	}
}

func TestCoverage_leavingFreesTheRoster(t *testing.T) {
	f := newCoverageFixture(t)
	ctx := context.Background()
	rec := f.do("admin", http.MethodPost, "/v1/receivers/r1/coverage-schedules",
		`{"user_id":"cg","rule":{"freq":"weekly","interval":1,"by_day":["TU"]},"start_time":"08:00","end_time":"16:00"}`)
	want(t, rec, http.StatusCreated)
	id := decode[coverageScheduleView](t, rec).CoverageScheduleID
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r1/assignments",
		`{"user_id":"cg","starts_local":"2026-11-12T08:00","ends_local":"2026-11-12T16:00"}`), http.StatusCreated)
	past := domain.Assignment{
		AssignmentID: "past", ReceiverID: "r1", TeamID: "t1", UserID: "cg", StartsLocal: "2026-11-01T08:00", EndsLocal: "2026-11-01T16:00",
		StartsAt: teamNow.Add(-7 * 24 * time.Hour), EndsAt: teamNow.Add(-7*24*time.Hour + 8*time.Hour), Status: domain.AssignmentActive,
		CreatedBy: "admin", CreatedAt: teamNow.Add(-8 * 24 * time.Hour),
	}
	f.put(t, f.l.Names.Assignments, past)

	want(t, f.do("cg", http.MethodDelete, "/v1/teams/t1/members/cg", ""), http.StatusNoContent)

	want(t, f.do("cg", http.MethodGet, "/v1/receivers/r1/assignments", ""), http.StatusForbidden)
	rec = f.do("admin", http.MethodGet, "/v1/receivers/r1/assignments", "")
	want(t, rec, http.StatusOK)
	if ahead := decode[[]assignmentView](t, rec); len(ahead) != 0 {
		t.Fatalf("still ahead: %+v", ahead)
	}
	rec = f.do("admin", http.MethodGet, "/v1/receivers/r1/coverage-schedules", "")
	want(t, rec, http.StatusOK)
	rules := decode[[]coverageScheduleView](t, rec)
	if len(rules) != 1 || rules[0].EndsOn != "2026-11-08" || rules[0].CaregiverName != formerCaregiver {
		t.Fatalf("rule: %+v", rules)
	}
	if got, err := f.l.Stores.Assignments.Get(ctx, "past"); err != nil || got.Status != domain.AssignmentActive {
		t.Fatalf("past: %+v %v", got, err)
	}
	// The daily job makes nothing more for them.
	cs, _ := f.l.Stores.CoverageSchedules.Get(ctx, id)
	rc, _ := f.l.Stores.Receivers.Get(ctx, "r1")
	if res, err := generate.GenerateCoverage(ctx, f.l.Stores, cs, rc, teamNow, teamNow); err != nil || res.Written != 0 {
		t.Fatalf("regenerated: %+v %v", res, err)
	}
}

func TestCoverage_timeZoneChangeKeepsWallClock(t *testing.T) {
	f := newCoverageFixture(t)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r1/assignments",
		`{"user_id":"cg","starts_local":"2026-11-10T08:00","ends_local":"2026-11-10T16:00"}`), http.StatusCreated)
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r1", `{"name":"Grandma","time_zone":"America/New_York"}`), http.StatusOK)
	ahead := f.assignments(t, "/v1/receivers/r1/assignments")
	if len(ahead) != 1 || ahead[0].StartsLocal != "2026-11-10T08:00" || ahead[0].StartsAt != "2026-11-10T13:00:00Z" ||
		ahead[0].EndsAt != "2026-11-10T21:00:00Z" {
		t.Fatalf("retimed: %+v", ahead)
	}
}

func TestCoverage_restoreGeneratesAgain(t *testing.T) {
	f := newCoverageFixture(t)
	ctx := context.Background()
	cs := domain.CoverageSchedule{
		CoverageScheduleID: "cs-arch", ReceiverID: "r-arch", TeamID: "t1", UserID: "cg",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"TU"}}, StartTime: "08:00", EndTime: "16:00",
		StartsOn: "2026-11-01", CreatedBy: "admin", CreatedAt: teamNow, UpdatedAt: teamNow,
	}
	if err := f.l.Stores.CoverageSchedules.Create(ctx, cs); err != nil {
		t.Fatal(err)
	}
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r-arch/restore", ""), http.StatusNoContent)
	if ahead := f.assignments(t, "/v1/receivers/r-arch/assignments"); len(ahead) != 2 || ahead[0].StartsLocal != "2026-11-10T08:00" {
		t.Fatalf("after restore: %+v", ahead)
	}
}
