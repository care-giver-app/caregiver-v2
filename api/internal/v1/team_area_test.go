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
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

// teamNow is noon in Chicago.
var teamNow = time.Date(2026, 11, 8, 18, 0, 0, 0, time.UTC)

// teamFixture is team t1 (admin "admin" Ann, caregiver "cg" Cal) with an
// active receiver r1 in Chicago and an archived one, an outsider "out" on t2,
// and a closed user "gone".
type teamFixture struct {
	l   dynamotest.Local
	mux *http.ServeMux
	ids int
}

func newTeamFixture(t *testing.T) *teamFixture {
	t.Helper()
	l := dynamotest.StartLocal(t)
	f := &teamFixture{l: l}
	created := teamNow.Add(-30 * 24 * time.Hour)
	seedUser(t, l.Stores, domain.User{UserID: "admin", Email: "a@x.com", Name: "Ann", CreatedAt: created})
	seedUser(t, l.Stores, domain.User{UserID: "cg", Email: "c@x.com", Name: "cal", CreatedAt: created})
	seedUser(t, l.Stores, domain.User{UserID: "out", Email: "o@x.com", Name: "Oz", CreatedAt: created})
	seedUser(t, l.Stores, domain.User{UserID: "gone", Name: "", Status: domain.UserClosed, CreatedAt: created})
	seedTeam(t, l.Stores, "t1", "The Smiths", "admin", domain.TeamActive, created)
	seedTeam(t, l.Stores, "t2", "Elsewhere", "out", domain.TeamActive, created)
	seedTeam(t, l.Stores, "t-closed", "Closed", "admin", domain.TeamArchived, created)
	f.put(t, l.Names.Memberships, domain.NewMembership("cg", "t1", domain.RoleCaregiver, created))
	archivedAt := created.Add(time.Hour)
	for _, rc := range []domain.Receiver{
		{ReceiverID: "r1", TeamID: "t1", Name: "Grandma", TimeZone: "America/Chicago", Status: domain.ReceiverActive, CreatedAt: created},
		{ReceiverID: "r-arch", TeamID: "t1", Name: "Gone", TimeZone: "America/Chicago", Status: domain.ReceiverArchived,
			ArchivedBy: "gone", ArchivedAt: &archivedAt, CreatedAt: created},
		{ReceiverID: "r2", TeamID: "t2", Name: "Other", TimeZone: "UTC", Status: domain.ReceiverActive, CreatedAt: created},
	} {
		rc.CreatedBy = "admin"
		f.put(t, l.Names.Receivers, rc)
	}

	newID := func() string { f.ids++; return fmt.Sprintf("new-%d", f.ids) }
	now := func() time.Time { return teamNow }
	teams := NewTeams(l.Stores)
	teams.now, teams.newID = now, newID
	inv := NewInvitations(l.Stores)
	inv.now = now
	inv.newCode = func() (string, error) { return newID(), nil }
	rcv := NewReceivers(l.Stores)
	rcv.now, rcv.newID = now, newID
	trk := NewTrackers(l.Stores)
	trk.now, trk.newID = now, newID

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/teams/{teamId}", teams.Get)
	mux.HandleFunc("POST /v1/teams/{teamId}/close", teams.Close)
	mux.HandleFunc("GET /v1/teams/{teamId}/invitations", inv.ListByTeam)
	mux.HandleFunc("POST /v1/teams/{teamId}/invitations", inv.Create)
	mux.HandleFunc("PUT /v1/teams/{teamId}/members/{userId}", teams.ChangeRole)
	mux.HandleFunc("DELETE /v1/teams/{teamId}/members/{userId}", teams.RemoveMember)
	mux.HandleFunc("GET /v1/teams/{teamId}/my-notifications", teams.MyNotifications)
	mux.HandleFunc("PUT /v1/teams/{teamId}/my-notifications", teams.ChangeMyNotifications)
	mux.HandleFunc("GET /v1/teams/{teamId}/receivers", rcv.ListByTeam)
	mux.HandleFunc("POST /v1/teams/{teamId}/receivers", rcv.Create)
	mux.HandleFunc("GET /v1/receivers/{receiverId}", rcv.Get)
	mux.HandleFunc("PUT /v1/receivers/{receiverId}", rcv.Change)
	mux.HandleFunc("POST /v1/receivers/{receiverId}/archive", rcv.Archive)
	mux.HandleFunc("POST /v1/receivers/{receiverId}/restore", rcv.Restore)
	mux.HandleFunc("PUT /v1/receivers/{receiverId}/care-instructions", rcv.ChangeCareInstructions)
	mux.HandleFunc("PUT /v1/receivers/{receiverId}/emergency-contacts", rcv.ChangeEmergencyContacts)
	mux.HandleFunc("POST /v1/trackers/{trackerId}/pause", trk.Pause)
	f.mux = mux
	return f
}

func (f *teamFixture) put(t *testing.T, table string, v any) {
	t.Helper()
	item, err := store.MarshalItem(v)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.l.Client.PutItem(context.Background(), &dynamodb.PutItemInput{TableName: aws.String(table), Item: item}); err != nil {
		t.Fatal(err)
	}
}

func (f *teamFixture) do(as, method, path, body string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	f.mux.ServeHTTP(rec, asCaller(jsonRequest(method, path, body), as, as+"@x.com", map[string]string{"admin": "Ann", "cg": "cal"}[as]))
	return rec
}

func want(t *testing.T, rec *httptest.ResponseRecorder, code int) {
	t.Helper()
	if rec.Code != code {
		t.Fatalf("code=%d want %d body=%s", rec.Code, code, rec.Body.String())
	}
}

func TestTeam_GetAndAccess(t *testing.T) {
	f := newTeamFixture(t)
	f.put(t, f.l.Names.Memberships, domain.NewMembership("gone", "t1", domain.RoleAdmin, teamNow))

	rec := f.do("cg", http.MethodGet, "/v1/teams/t1", "")
	want(t, rec, http.StatusOK)
	got := decode[teamDetail](t, rec)
	// Admins first, then by name ignoring case: "a former caregiver" < "Ann".
	if got.Name != "The Smiths" || got.MyRole != "caregiver" || len(got.Members) != 3 ||
		got.Members[0] != (teamMember{UserID: "gone", Name: formerCaregiver, Role: "admin"}) ||
		got.Members[1] != (teamMember{UserID: "admin", Name: "Ann", Role: "admin"}) ||
		got.Members[2] != (teamMember{UserID: "cg", Name: "cal", Role: "caregiver"}) {
		t.Fatalf("detail: %+v", got)
	}
	want(t, f.do("out", http.MethodGet, "/v1/teams/t1", ""), http.StatusForbidden)
	want(t, f.do("admin", http.MethodGet, "/v1/teams/missing", ""), http.StatusNotFound)
	want(t, f.do("admin", http.MethodGet, "/v1/teams/t-closed", ""), http.StatusNotFound)
}

func TestTeam_RolesAndLeaving(t *testing.T) {
	f := newTeamFixture(t)
	ctx := context.Background()

	// Caregivers cannot change roles or remove anyone but themselves.
	want(t, f.do("cg", http.MethodPut, "/v1/teams/t1/members/admin", `{"role":"caregiver"}`), http.StatusForbidden)
	want(t, f.do("cg", http.MethodDelete, "/v1/teams/t1/members/admin", ""), http.StatusForbidden)
	want(t, f.do("out", http.MethodDelete, "/v1/teams/t1/members/out", ""), http.StatusForbidden)

	// The only admin can neither demote themselves nor leave.
	want(t, f.do("admin", http.MethodPut, "/v1/teams/t1/members/admin", `{"role":"caregiver"}`), http.StatusConflict)
	want(t, f.do("admin", http.MethodDelete, "/v1/teams/t1/members/admin", ""), http.StatusConflict)
	want(t, f.do("admin", http.MethodPut, "/v1/teams/t1/members/cg", `{"role":"owner"}`), http.StatusBadRequest)
	want(t, f.do("admin", http.MethodPut, "/v1/teams/t1/members/out", `{"role":"admin"}`), http.StatusNotFound)
	want(t, f.do("admin", http.MethodDelete, "/v1/teams/t1/members/out", ""), http.StatusNotFound)

	// Promote Cal; now Ann may leave, and Cal is the only admin.
	rec := f.do("admin", http.MethodPut, "/v1/teams/t1/members/cg", `{"role":"admin"}`)
	want(t, rec, http.StatusOK)
	if got := decode[teamMember](t, rec); got != (teamMember{UserID: "cg", Name: "cal", Role: "admin"}) {
		t.Fatalf("promoted: %+v", got)
	}
	want(t, f.do("admin", http.MethodDelete, "/v1/teams/t1/members/admin", ""), http.StatusNoContent)
	if _, err := f.l.Stores.Memberships.Get(ctx, "admin", "t1"); err == nil {
		t.Fatal("left but still a member")
	}
	want(t, f.do("cg", http.MethodDelete, "/v1/teams/t1/members/cg", ""), http.StatusConflict)

	// A caregiver may leave; an admin may remove one.
	f.put(t, f.l.Names.Memberships, domain.NewMembership("admin", "t1", domain.RoleCaregiver, teamNow))
	want(t, f.do("admin", http.MethodDelete, "/v1/teams/t1/members/admin", ""), http.StatusNoContent)
	f.put(t, f.l.Names.Memberships, domain.NewMembership("admin", "t1", domain.RoleCaregiver, teamNow))
	want(t, f.do("cg", http.MethodDelete, "/v1/teams/t1/members/admin", ""), http.StatusNoContent)
}

func TestTeam_Close(t *testing.T) {
	f := newTeamFixture(t)
	want(t, f.do("admin", http.MethodPost, "/v1/teams/t1/close", ""), http.StatusConflict)
	want(t, f.do("out", http.MethodPost, "/v1/teams/t1/close", ""), http.StatusForbidden)
	want(t, f.do("cg", http.MethodDelete, "/v1/teams/t1/members/cg", ""), http.StatusNoContent)

	// r1 has a routine with occurrences still to come.
	ctx := context.Background()
	s := f.l.Stores
	tr := domain.Tracker{TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1", Name: "Meds", Status: domain.TrackerActive, CreatedAt: teamNow}
	f.put(t, f.l.Names.Trackers, tr)
	sc := domain.Schedule{ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: domain.FreqWeekly, Interval: 1, ByDay: []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}},
		Time: "08:00", StartsOn: "2026-11-01", PlannedValues: map[string]any{}, CreatedAt: teamNow, UpdatedAt: teamNow}
	f.put(t, f.l.Names.Schedules, sc)
	rc, _ := s.Receivers.Get(ctx, "r1")
	if res, err := generate.Generate(ctx, s, sc, tr, rc, teamNow, teamNow); err != nil || res.Written == 0 {
		t.Fatalf("generate: %+v %v", res, err)
	}

	want(t, f.do("admin", http.MethodPost, "/v1/teams/t1/close", ""), http.StatusNoContent)
	if es, err := s.Entries.FutureOpenByReceiver(ctx, "r1", teamNow); err != nil || len(es) != 0 {
		t.Fatalf("close left %d waiting (err %v)", len(es), err)
	}
	if rc, _ := s.Receivers.Get(ctx, "r1"); rc.Status != domain.ReceiverActive {
		t.Fatalf("receiver status changed: %+v", rc)
	}
	// And the generator makes no more for a closed team.
	if res, err := generate.Generate(ctx, s, sc, tr, rc, teamNow, teamNow); err != nil || !res.Skipped {
		t.Fatalf("generate after close: %+v %v", res, err)
	}
	if es, _ := s.Entries.FutureOpenByReceiver(ctx, "r1", teamNow); len(es) != 0 {
		t.Fatalf("generated %d for a closed team", len(es))
	}
	team, _ := f.l.Stores.Teams.Get(context.Background(), "t1")
	if team.Status != domain.TeamArchived || team.ArchivedBy != "admin" || !team.ArchivedAt.Equal(teamNow) {
		t.Fatalf("team: %+v", team)
	}
	want(t, f.do("admin", http.MethodGet, "/v1/teams/t1", ""), http.StatusNotFound)
}

func TestTeam_Invitations(t *testing.T) {
	f := newTeamFixture(t)
	seedInvite(t, f.l.Stores, "old", "t1", "p@x.com", "gone", domain.InvitePending, teamNow.Add(24*time.Hour))
	seedInvite(t, f.l.Stores, "expired", "t1", "q@x.com", "admin", domain.InvitePending, teamNow)
	seedInvite(t, f.l.Stores, "used", "t1", "r@x.com", "admin", domain.InviteAccepted, teamNow.Add(24*time.Hour))
	seedInvite(t, f.l.Stores, "theirs", "t2", "s@x.com", "out", domain.InvitePending, teamNow.Add(24*time.Hour))

	want(t, f.do("cg", http.MethodPost, "/v1/teams/t1/invitations", `{"email":"n@x.com"}`), http.StatusForbidden)
	want(t, f.do("cg", http.MethodGet, "/v1/teams/t1/invitations", ""), http.StatusForbidden)
	want(t, f.do("admin", http.MethodPost, "/v1/teams/t1/invitations", `{"email":"not an email"}`), http.StatusBadRequest)
	// An address that belongs to someone on the team, however it is written.
	want(t, f.do("admin", http.MethodPost, "/v1/teams/t1/invitations", `{"email":" C@X.com "}`), http.StatusConflict)

	rec := f.do("admin", http.MethodPost, "/v1/teams/t1/invitations", `{"email":"New@X.com"}`)
	want(t, rec, http.StatusCreated)
	created := decode[teamInvitation](t, rec)
	if created.Code != "new-1" || created.Email != "new@x.com" || created.InvitedByName != "Ann" ||
		created.CreatedAt != "2026-11-08T18:00:00Z" || created.ExpiresAt != "2026-11-22T18:00:00Z" {
		t.Fatalf("created: %+v", created)
	}
	inv, err := f.l.Stores.Invitations.Get(context.Background(), "new-1")
	if err != nil || inv.TeamID != "t1" || inv.Status != domain.InvitePending || inv.InvitedBy != "admin" {
		t.Fatalf("stored: %+v %v", inv, err)
	}
	// A second to the same address is allowed.
	want(t, f.do("admin", http.MethodPost, "/v1/teams/t1/invitations", `{"email":"new@x.com"}`), http.StatusCreated)

	rec = f.do("admin", http.MethodGet, "/v1/teams/t1/invitations", "")
	want(t, rec, http.StatusOK)
	list := decode[[]teamInvitation](t, rec)
	var codes []string
	for _, i := range list {
		codes = append(codes, i.Code)
	}
	if strings.Join(codes, ",") != "new-1,new-2,old" && strings.Join(codes, ",") != "new-2,new-1,old" {
		t.Fatalf("list: %v", codes)
	}
	if list[2].InvitedByName != formerCaregiver {
		t.Fatalf("closed inviter: %+v", list[2])
	}
}

func TestTeam_MyNotifications(t *testing.T) {
	f := newTeamFixture(t)
	rec := f.do("cg", http.MethodGet, "/v1/teams/t1/my-notifications", "")
	want(t, rec, http.StatusOK)
	if rec.Body.String() != `{"reminders":true,"range_alerts":true,"gap_alerts":true,"unrecorded_alerts":true}`+"\n" {
		t.Fatalf("defaults: %s", rec.Body.String())
	}
	want(t, f.do("cg", http.MethodPut, "/v1/teams/t1/my-notifications", `{"reminders":false}`), http.StatusBadRequest)
	rec = f.do("cg", http.MethodPut, "/v1/teams/t1/my-notifications",
		`{"reminders":false,"range_alerts":true,"gap_alerts":false,"unrecorded_alerts":true}`)
	want(t, rec, http.StatusOK)
	m, _ := f.l.Stores.Memberships.Get(context.Background(), "cg", "t1")
	if m.NotifyReminders || !m.NotifyRangeAlerts || m.NotifyGapAlerts || !m.NotifyUnrecordedAlerts {
		t.Fatalf("stored: %+v", m)
	}
	if a, _ := f.l.Stores.Memberships.Get(context.Background(), "admin", "t1"); !a.NotifyReminders || !a.NotifyGapAlerts {
		t.Fatalf("someone else's changed: %+v", a)
	}
	want(t, f.do("out", http.MethodGet, "/v1/teams/t1/my-notifications", ""), http.StatusForbidden)
	want(t, f.do("out", http.MethodPut, "/v1/teams/t1/my-notifications",
		`{"reminders":false,"range_alerts":true,"gap_alerts":false,"unrecorded_alerts":true}`), http.StatusForbidden)
}

func TestReceivers_ListAddAndGet(t *testing.T) {
	f := newTeamFixture(t)
	ids := func(rec *httptest.ResponseRecorder) string {
		var out []string
		for _, r := range decode[[]careReceiver](t, rec) {
			out = append(out, r.ReceiverID)
		}
		return strings.Join(out, ",")
	}
	rec := f.do("cg", http.MethodGet, "/v1/teams/t1/receivers", "")
	want(t, rec, http.StatusOK)
	if got := ids(rec); got != "r1" {
		t.Fatalf("active: %s", got)
	}
	rec = f.do("cg", http.MethodGet, "/v1/teams/t1/receivers?status=archived", "")
	want(t, rec, http.StatusOK)
	if got := ids(rec); got != "r-arch" {
		t.Fatalf("archived: %s", got)
	}
	want(t, f.do("cg", http.MethodGet, "/v1/teams/t1/receivers?status=gone", ""), http.StatusBadRequest)

	want(t, f.do("cg", http.MethodPost, "/v1/teams/t1/receivers", `{"name":"Pop","time_zone":"UTC"}`), http.StatusForbidden)
	for _, body := range []string{`{"name":"Pop","time_zone":"Mars/Base"}`, `{"name":"Pop","time_zone":"Local"}`,
		`{"name":"Pop"}`, `{"name":" ","time_zone":"UTC"}`} {
		want(t, f.do("admin", http.MethodPost, "/v1/teams/t1/receivers", body), http.StatusBadRequest)
	}
	rec = f.do("admin", http.MethodPost, "/v1/teams/t1/receivers", `{"name":" Pop ","time_zone":"Europe/London"}`)
	want(t, rec, http.StatusCreated)
	if got := decode[careReceiver](t, rec); got != (careReceiver{ReceiverID: "new-1", TeamID: "t1", Name: "Pop", TimeZone: "Europe/London"}) {
		t.Fatalf("created: %+v", got)
	}

	// Care receiver: archived or not, empty instructions omitted, contacts [].
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r-arch", "")
	want(t, rec, http.StatusOK)
	body := rec.Body.String()
	if !strings.Contains(body, `"team_name":"The Smiths"`) || !strings.Contains(body, `"status":"archived"`) ||
		!strings.Contains(body, `"archived_by_name":"a former caregiver"`) || !strings.Contains(body, `"emergency_contacts":[]`) ||
		strings.Contains(body, "care_instructions") {
		t.Fatalf("archived detail: %s", body)
	}
	rec = f.do("cg", http.MethodGet, "/v1/receivers/r1", "")
	want(t, rec, http.StatusOK)
	if b := rec.Body.String(); strings.Contains(b, "archived") || !strings.Contains(b, `"status":"active"`) {
		t.Fatalf("active detail: %s", b)
	}
	want(t, f.do("out", http.MethodGet, "/v1/receivers/r1", ""), http.StatusForbidden)
	want(t, f.do("cg", http.MethodGet, "/v1/receivers/missing", ""), http.StatusNotFound)
}

func TestReceivers_CareInstructionsAndContacts(t *testing.T) {
	f := newTeamFixture(t)
	ctx := context.Background()

	want(t, f.do("cg", http.MethodPut, "/v1/receivers/r1/care-instructions", `{"body":"x"}`), http.StatusForbidden)
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r1/care-instructions", `{}`), http.StatusBadRequest)
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r1/care-instructions",
		`{"body":"`+strings.Repeat("a", 20001)+`"}`), http.StatusBadRequest)
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r-arch/care-instructions", `{"body":"x"}`), http.StatusConflict)
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r-arch/emergency-contacts", `{"contacts":[]}`), http.StatusConflict)

	rec := f.do("admin", http.MethodPut, "/v1/receivers/r1/care-instructions", `{"body":"Pills at 8."}`)
	want(t, rec, http.StatusOK)
	d := decode[careReceiverDetail](t, rec)
	if d.CareInstructions == nil || *d.CareInstructions != (careInstructionsView{Body: "Pills at 8.", UpdatedByName: "Ann", UpdatedAt: "2026-11-08T18:00:00Z"}) {
		t.Fatalf("instructions: %+v", d.CareInstructions)
	}

	// Contacts, changed by someone else later, do not move the stamp.
	f.put(t, f.l.Names.Memberships, domain.NewMembership("cg", "t1", domain.RoleAdmin, teamNow))
	rec = f.do("cg", http.MethodPut, "/v1/receivers/r1/emergency-contacts",
		`{"contacts":[{"name":"Dr Lee","relationship":"GP","phone":"555-1"},{"name":"Sam","relationship":"Son","phone":"555-2"}]}`)
	want(t, rec, http.StatusOK)
	d = decode[careReceiverDetail](t, rec)
	if len(d.EmergencyContacts) != 2 || d.EmergencyContacts[0].ContactID != "new-1" || d.EmergencyContacts[1].ContactID != "new-2" ||
		d.CareInstructions.UpdatedByName != "Ann" {
		t.Fatalf("contacts: %+v", d)
	}
	ci, _ := f.l.Stores.CareInstructions.Get(ctx, "r1")
	if ci.UpdatedBy != "admin" || !ci.UpdatedAt.Equal(teamNow) {
		t.Fatalf("stamp moved: %+v", ci)
	}
	// Reorder, keep one by id, drop the other, add a third.
	rec = f.do("cg", http.MethodPut, "/v1/receivers/r1/emergency-contacts",
		`{"contacts":[{"name":"Nurse","relationship":"","phone":"555-3"},{"contact_id":"new-1","name":"Dr Lee","relationship":"GP","phone":"555-9"}]}`)
	want(t, rec, http.StatusOK)
	d = decode[careReceiverDetail](t, rec)
	if len(d.EmergencyContacts) != 2 || d.EmergencyContacts[0].ContactID != "new-3" ||
		d.EmergencyContacts[1] != (emergencyContact{ContactID: "new-1", Name: "Dr Lee", Relationship: "GP", Phone: "555-9"}) {
		t.Fatalf("replaced: %+v", d.EmergencyContacts)
	}
	want(t, f.do("cg", http.MethodPut, "/v1/receivers/r1/emergency-contacts",
		`{"contacts":[{"contact_id":"nope","name":"x","phone":"1"}]}`), http.StatusBadRequest)

	// An empty body clears the instructions; the contacts stay.
	rec = f.do("admin", http.MethodPut, "/v1/receivers/r1/care-instructions", `{"body":"  "}`)
	want(t, rec, http.StatusOK)
	if b := rec.Body.String(); strings.Contains(b, "care_instructions") || !strings.Contains(b, "new-3") {
		t.Fatalf("cleared: %s", b)
	}
}

func TestReceivers_ArchiveRestoreAndTimeZone(t *testing.T) {
	f := newTeamFixture(t)
	ctx := context.Background()
	s := f.l.Stores
	tr := domain.Tracker{TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1", Name: "Meds", Status: domain.TrackerActive, CreatedAt: teamNow}
	paused := domain.Tracker{TrackerID: "tr-p", ReceiverID: "r1", TeamID: "t1", Name: "Walk", Status: domain.TrackerPaused, CreatedAt: teamNow}
	f.put(t, f.l.Names.Trackers, tr)
	f.put(t, f.l.Names.Trackers, paused)
	for _, sc := range []domain.Schedule{
		{ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1"},
		{ScheduleID: "s-p", TrackerID: "tr-p", ReceiverID: "r1", TeamID: "t1"},
	} {
		sc.Rule = domain.Rule{Freq: domain.FreqWeekly, Interval: 1, ByDay: []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}}
		sc.Time, sc.StartsOn, sc.PlannedValues, sc.CreatedAt, sc.UpdatedAt = "08:00", "2026-11-01", map[string]any{}, teamNow, teamNow
		f.put(t, f.l.Names.Schedules, sc)
	}
	rc, _ := s.Receivers.Get(ctx, "r1")
	sc, _ := s.Schedules.Get(ctx, "s1")
	if _, err := generate.Generate(ctx, s, sc, tr, rc, teamNow, teamNow); err != nil {
		t.Fatal(err)
	}
	// This morning's, already unrecorded, and one logged: archiving keeps both.
	morningAt := time.Date(2026, 11, 8, 14, 0, 0, 0, time.UTC)
	morning := domain.Entry{EntryID: generate.EntryID("s1", "2026-11-08T08:00"), TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		ScheduleID: "s1", OccurrenceLocal: "2026-11-08T08:00", OccurrenceAt: &morningAt, State: domain.EntryScheduled,
		Values: map[string]any{}, CreatedAt: teamNow, TimelineAt: morningAt, OpenAt: &morningAt}
	f.put(t, f.l.Names.Entries, morning)
	future := func() []domain.Entry {
		t.Helper()
		es, err := s.Entries.FutureOpenByReceiver(ctx, "r1", teamNow)
		if err != nil {
			t.Fatal(err)
		}
		return es
	}
	generated := len(future())
	if generated == 0 {
		t.Fatal("nothing generated")
	}

	// Time zone: only what is still to come moves, keeping 08:00.
	want(t, f.do("cg", http.MethodPut, "/v1/receivers/r1", `{"name":"Grandma","time_zone":"America/New_York"}`), http.StatusForbidden)
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r1", `{"name":"Grandma","time_zone":"Nowhere"}`), http.StatusBadRequest)
	rec := f.do("admin", http.MethodPut, "/v1/receivers/r1", `{"name":"Nana","time_zone":"America/New_York"}`)
	want(t, rec, http.StatusOK)
	if got := decode[careReceiver](t, rec); got.Name != "Nana" || got.TimeZone != "America/New_York" {
		t.Fatalf("changed: %+v", got)
	}
	ny, _ := time.LoadLocation("America/New_York")
	for _, e := range future() {
		if e.OccurrenceAt.In(ny).Format("15:04") != "08:00" || !e.OpenAt.Equal(*e.OccurrenceAt) || !e.TimelineAt.Equal(*e.OccurrenceAt) {
			t.Fatalf("not re-resolved: %+v", e)
		}
	}
	if m, _ := s.Entries.Get(ctx, morning.EntryID); !m.OccurrenceAt.Equal(morningAt) {
		t.Fatalf("past entry moved: %+v", m)
	}

	// Archive: idempotent, removes only what is still to come.
	want(t, f.do("cg", http.MethodPost, "/v1/receivers/r1/archive", ""), http.StatusForbidden)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r1/archive", ""), http.StatusNoContent)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r1/archive", ""), http.StatusNoContent)
	if es := future(); len(es) != 0 {
		t.Fatalf("archive left %d waiting", len(es))
	}
	if m, err := s.Entries.Get(ctx, morning.EntryID); err != nil || m.State != domain.EntryScheduled {
		t.Fatalf("past entry removed: %+v %v", m, err)
	}
	rc, _ = s.Receivers.Get(ctx, "r1")
	if rc.Status != domain.ReceiverArchived || rc.ArchivedBy != "admin" {
		t.Fatalf("receiver: %+v", rc)
	}
	want(t, f.do("admin", http.MethodPut, "/v1/receivers/r1", `{"name":"x","time_zone":"UTC"}`), http.StatusConflict)

	// Restore: idempotent, regenerates the trackers not paused, from now.
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r1/restore", ""), http.StatusNoContent)
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/r1/restore", ""), http.StatusNoContent)
	es := future()
	if len(es) != generated {
		t.Fatalf("restore made %d, want %d", len(es), generated)
	}
	for _, e := range es {
		if e.TrackerID != "tr1" || e.OccurrenceAt.In(ny).Format("15:04") != "08:00" {
			t.Fatalf("restored: %+v", e)
		}
	}
	if rc, _ = s.Receivers.Get(ctx, "r1"); rc.Status != domain.ReceiverActive || rc.ArchivedAt != nil {
		t.Fatalf("receiver: %+v", rc)
	}
	want(t, f.do("admin", http.MethodPost, "/v1/receivers/missing/archive", ""), http.StatusNotFound)
}

// A closed team's receivers are unreachable on every receiver route, read or
// write, even to someone whose membership survived the close (a caregiver who
// joined as it closed). admin is still an admin of t-closed here.
func TestReceivers_closedTeamIsNotFound(t *testing.T) {
	f := newTeamFixture(t)
	f.put(t, f.l.Names.Receivers, domain.Receiver{ReceiverID: "r-closed", TeamID: "t-closed", Name: "Pat",
		TimeZone: "UTC", Status: domain.ReceiverActive, CreatedBy: "admin", CreatedAt: teamNow})
	f.put(t, f.l.Names.Trackers, domain.Tracker{TrackerID: "tr-closed", ReceiverID: "r-closed", TeamID: "t-closed",
		Name: "Meds", Status: domain.TrackerActive, CreatedAt: teamNow})
	for _, c := range []struct{ method, path, body string }{
		{http.MethodGet, "/v1/receivers/r-closed", ""},
		{http.MethodPut, "/v1/receivers/r-closed", `{"name":"Pat","time_zone":"UTC"}`},
		{http.MethodPost, "/v1/receivers/r-closed/archive", ""},
		{http.MethodPost, "/v1/receivers/r-closed/restore", ""},
		{http.MethodPut, "/v1/receivers/r-closed/care-instructions", `{"body":"x"}`},
		{http.MethodPut, "/v1/receivers/r-closed/emergency-contacts", `{"contacts":[]}`},
		{http.MethodPost, "/v1/trackers/tr-closed/pause", ""},
	} {
		t.Run(c.method+" "+c.path, func(t *testing.T) {
			want(t, f.do("admin", c.method, c.path, c.body), http.StatusNotFound)
		})
	}
	if rc, _ := f.l.Stores.Receivers.Get(context.Background(), "r-closed"); rc.Status != domain.ReceiverActive || rc.Name != "Pat" {
		t.Fatalf("closed team's receiver changed: %+v", rc)
	}
}
