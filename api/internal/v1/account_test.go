package v1

import (
	"context"
	"errors"
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

// fakeIdentity is an IdentityProvider whose answers a test sets.
type fakeIdentity struct {
	password   string // the one right password, for every account
	checkErr   error  // returned by CheckPassword instead, when set
	changeErr  error
	deleteErr  error
	checkedAs  []string
	changes    []string // "userID→email"
	deleted    []string
	deleteCall int
}

func (f *fakeIdentity) CheckPassword(_ context.Context, signIn, password string) error {
	f.checkedAs = append(f.checkedAs, signIn)
	if f.checkErr != nil {
		return f.checkErr
	}
	if password != f.password {
		return ErrWrongPassword
	}
	return nil
}

func (f *fakeIdentity) StartEmailChange(_ context.Context, userID, email string) error {
	if f.changeErr != nil {
		return f.changeErr
	}
	f.changes = append(f.changes, userID+"→"+email)
	return nil
}

func (f *fakeIdentity) DeleteUser(_ context.Context, userID string) error {
	f.deleteCall++
	if f.deleteErr != nil {
		return f.deleteErr
	}
	f.deleted = append(f.deleted, userID)
	return nil
}

func serve(h http.HandlerFunc, r *http.Request) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h(rec, r)
	return rec
}

func TestAccount_Change(t *testing.T) {
	s := dynamotest.Start(t)
	h := NewAccount(s, &fakeIdentity{})
	seedUser(t, s, domain.User{UserID: "u1", Email: "u1@x.com", Name: "Sam", EmailNotifications: true})
	patch := func(body string) *httptest.ResponseRecorder {
		return serve(h.Change, asCaller(jsonRequest(http.MethodPatch, "/v1/me", body), "u1", "u1@x.com", "Sam"))
	}

	rec := patch(`{"name":"  Sam Lee  "}`)
	want := `{"user_id":"u1","email":"u1@x.com","name":"Sam Lee","email_notifications":true}`
	if rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != want {
		t.Fatalf("rename: %d %s", rec.Code, rec.Body.String())
	}
	rec = patch(`{"email_notifications":false}`)
	if got := decode[caregiverView](t, rec); rec.Code != http.StatusOK || got.Name != "Sam Lee" || got.EmailNotifications {
		t.Fatalf("notifications off: %d %s", rec.Code, rec.Body.String())
	}
	if u, _ := s.Users.Get(context.Background(), "u1"); u.Name != "Sam Lee" || u.EmailNotifications {
		t.Fatalf("stored = %+v", u)
	}

	for name, body := range map[string]string{
		"empty body":     `{}`,
		"unknown only":   `{"email":"x@y.com"}`,
		"blank name":     `{"name":"   "}`,
		"long name":      `{"name":"` + strings.Repeat("é", 101) + `"}`,
		"not json":       `nope`,
		"wrong type":     `{"email_notifications":"yes"}`,
		"null both ways": `{"name":null,"email_notifications":null}`,
	} {
		if rec := patch(body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code=%d", name, rec.Code)
		}
	}
	if rec := patch(`{"name":"` + strings.Repeat("é", 100) + `"}`); rec.Code != http.StatusOK {
		t.Fatalf("100 characters: %d", rec.Code)
	}

	if rec := serve(h.Change, jsonRequest(http.MethodPatch, "/v1/me", `{"name":"X"}`)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no caller: %d", rec.Code)
	}
}

func TestAccount_StartEmailChange(t *testing.T) {
	s := dynamotest.Start(t)
	idp := &fakeIdentity{password: "right"}
	h := NewAccount(s, idp)
	seedUser(t, s, domain.User{UserID: "u1", Email: "u1@x.com", Name: "Sam"})
	seedUser(t, s, domain.User{UserID: "u2", Email: "taken@x.com", Name: "Jo"})
	post := func(body string) *httptest.ResponseRecorder {
		return serve(h.StartEmailChange, asCaller(jsonRequest(http.MethodPost, "/v1/me/email", body), "u1", "u1@x.com", "Sam"))
	}

	if rec := post(`{"current_password":"right","new_email":" New@X.com "}`); rec.Code != http.StatusNoContent {
		t.Fatalf("send code: %d %s", rec.Code, rec.Body.String())
	}
	if len(idp.changes) != 1 || idp.changes[0] != "u1→new@x.com" || idp.checkedAs[0] != "u1@x.com" {
		t.Fatalf("changes=%v checkedAs=%v", idp.changes, idp.checkedAs)
	}
	if u, _ := s.Users.Get(context.Background(), "u1"); u.Email != "u1@x.com" {
		t.Fatalf("the row must keep the old address until the code is confirmed: %q", u.Email)
	}

	if rec := post(`{"current_password":"wrong","new_email":"new@x.com"}`); rec.Code != http.StatusForbidden ||
		!strings.Contains(rec.Body.String(), msgWrongPassword) {
		t.Fatalf("wrong password: %d %s", rec.Code, rec.Body.String())
	}
	if rec := post(`{"current_password":"right","new_email":"taken@x.com"}`); rec.Code != http.StatusConflict {
		t.Fatalf("held by another row: %d", rec.Code)
	}
	if len(idp.changes) != 1 {
		t.Fatalf("no code may be sent for an address in use: %v", idp.changes)
	}

	idp.changeErr = ErrEmailInUse
	if rec := post(`{"current_password":"right","new_email":"cognito-only@x.com"}`); rec.Code != http.StatusConflict {
		t.Fatalf("refused by the identity provider: %d", rec.Code)
	}
	idp.changeErr = nil

	idp.checkErr = ErrTooManyAttempts
	if rec := post(`{"current_password":"right","new_email":"new@x.com"}`); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("too many attempts: %d", rec.Code)
	}
	idp.checkErr = errors.New("cognito is down")
	if rec := post(`{"current_password":"right","new_email":"new@x.com"}`); rec.Code != http.StatusInternalServerError {
		t.Fatalf("provider failure: %d", rec.Code)
	}
	idp.checkErr = nil

	for name, body := range map[string]string{
		"no password":   `{"new_email":"new@x.com"}`,
		"no address":    `{"current_password":"right"}`,
		"bad address":   `{"current_password":"right","new_email":"not an address"}`,
		"display name":  `{"current_password":"right","new_email":"Sam <s@x.com>"}`,
		"same address":  `{"current_password":"right","new_email":"U1@x.com"}`,
		"not json":      `{`,
		"wrong type":    `{"current_password":1,"new_email":"new@x.com"}`,
		"empty request": `{}`,
	} {
		if rec := post(body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code=%d", name, rec.Code)
		}
	}
}

func TestAccount_Close(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 11, 20, 15, 0, 0, 0, time.UTC)
	var l dynamotest.Local
	setup := func(t *testing.T) (*store.Stores, *fakeIdentity, *Account) {
		l = dynamotest.StartLocal(t)
		s := l.Stores
		idp := &fakeIdentity{password: "right"}
		h := NewAccount(s, idp)
		h.now = func() time.Time { return now }
		seedUser(t, s, domain.User{UserID: "sam", Email: "sam@x.com", Name: "Sam"})
		seedUser(t, s, domain.User{UserID: "alex", Email: "alex@x.com", Name: "Alex"})
		return s, idp, h
	}
	join := func(t *testing.T, s *store.Stores, userID, teamID string, role domain.Role) {
		t.Helper()
		item, err := store.MarshalItem(domain.NewMembership(userID, teamID, role, now))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := l.Client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(l.Names.Memberships), Item: item}); err != nil {
			t.Fatalf("join %s %s: %v", userID, teamID, err)
		}
	}
	closeAs := func(h *Account, closed bool, body string) *httptest.ResponseRecorder {
		r := jsonRequest(http.MethodPost, "/v1/me/close", body)
		r = r.WithContext(withCaller(r.Context(), &caller{UserID: "sam", Email: "sam@x.com", Name: "Sam", Closed: closed}))
		return serve(h.Close, r)
	}

	t.Run("closes, leaving every team and the sign-in", func(t *testing.T) {
		s, idp, h := setup(t)
		seedTeam(t, s, "t1", "Riverside", "alex", domain.TeamActive, now)
		seedTeam(t, s, "t2", "Hillside", "alex", domain.TeamActive, now)
		join(t, s, "sam", "t1", domain.RoleCaregiver)
		join(t, s, "sam", "t2", domain.RoleAdmin) // Alex is an admin there too

		if rec := closeAs(h, false, `{"password":"right"}`); rec.Code != http.StatusNoContent {
			t.Fatalf("close: %d %s", rec.Code, rec.Body.String())
		}
		if ms, _ := s.Memberships.ListByUser(ctx, "sam"); len(ms) != 0 {
			t.Fatalf("memberships left: %+v", ms)
		}
		u, err := s.Users.Get(ctx, "sam")
		if err != nil || u.Status != domain.UserClosed || u.Name != "" || u.Email != "" || u.ClosedAt == nil || !u.ClosedAt.Equal(now) {
			t.Fatalf("row = %+v %v", u, err)
		}
		if len(idp.deleted) != 1 || idp.deleted[0] != "sam" {
			t.Fatalf("deleted = %v", idp.deleted)
		}
		if m, err := s.Memberships.Get(ctx, "alex", "t2"); err != nil || m.Role != domain.RoleAdmin {
			t.Fatalf("the other admin is untouched: %+v %v", m, err)
		}
	})

	t.Run("refused while the only admin, naming every such team", func(t *testing.T) {
		s, idp, h := setup(t)
		seedTeam(t, s, "t-alone", "Zeta", "sam", domain.TeamActive, now)
		seedTeam(t, s, "t-sole", "Alpha", "sam", domain.TeamActive, now)
		join(t, s, "alex", "t-sole", domain.RoleCaregiver)
		seedTeam(t, s, "t-other", "Beta", "alex", domain.TeamActive, now)
		join(t, s, "sam", "t-other", domain.RoleCaregiver)

		rec := closeAs(h, false, `{"password":"right"}`)
		want := `{"message":"` + msgSoleAdmin + `","teams":[{"team_id":"t-sole","name":"Alpha"},{"team_id":"t-alone","name":"Zeta"}]}`
		if rec.Code != http.StatusConflict || strings.TrimSpace(rec.Body.String()) != want {
			t.Fatalf("refusal: %d %s", rec.Code, rec.Body.String())
		}
		if ms, _ := s.Memberships.ListByUser(ctx, "sam"); len(ms) != 3 {
			t.Fatalf("nothing may be left before refusing: %+v", ms)
		}
		if u, _ := s.Users.Get(ctx, "sam"); u.Status != domain.UserActive || u.Name != "Sam" {
			t.Fatalf("row changed: %+v", u)
		}
		if idp.deleteCall != 0 {
			t.Fatal("the sign-in must stay")
		}
	})

	t.Run("wrong password, too many attempts, bad body", func(t *testing.T) {
		s, idp, h := setup(t)
		if rec := closeAs(h, false, `{"password":"wrong"}`); rec.Code != http.StatusForbidden {
			t.Fatalf("wrong password: %d", rec.Code)
		}
		idp.checkErr = ErrTooManyAttempts
		if rec := closeAs(h, false, `{"password":"right"}`); rec.Code != http.StatusTooManyRequests {
			t.Fatalf("too many: %d", rec.Code)
		}
		idp.checkErr = nil
		for _, body := range []string{`{}`, `{"password":""}`, `nope`} {
			if rec := closeAs(h, false, body); rec.Code != http.StatusBadRequest {
				t.Fatalf("%s: %d", body, rec.Code)
			}
		}
		if u, _ := s.Users.Get(ctx, "sam"); u.Status != domain.UserActive || idp.deleteCall != 0 {
			t.Fatalf("nothing may change: %+v", u)
		}
	})

	t.Run("a close stopped before the sign-in went finishes when sent again", func(t *testing.T) {
		s, idp, h := setup(t)
		seedTeam(t, s, "t1", "Riverside", "alex", domain.TeamActive, now)
		join(t, s, "sam", "t1", domain.RoleCaregiver)
		idp.deleteErr = errors.New("cognito is down")
		if rec := closeAs(h, false, `{"password":"right"}`); rec.Code != http.StatusInternalServerError {
			t.Fatalf("first try: %d", rec.Code)
		}
		if u, _ := s.Users.Get(ctx, "sam"); u.Status != domain.UserClosed || u.Name != "" {
			t.Fatalf("the row is closed even so: %+v", u)
		}
		idp.deleteErr = nil
		// The authenticator serves this route to the closed row, marked Closed.
		if rec := closeAs(h, true, `{"password":"right"}`); rec.Code != http.StatusNoContent {
			t.Fatalf("retry: %d %s", rec.Code, rec.Body.String())
		}
		if len(idp.deleted) != 1 {
			t.Fatalf("deleted = %v", idp.deleted)
		}
		// A retry still checks the password.
		if rec := closeAs(h, true, `{"password":"wrong"}`); rec.Code != http.StatusForbidden {
			t.Fatalf("retry with wrong password: %d", rec.Code)
		}
	})
}
