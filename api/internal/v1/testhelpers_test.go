package v1

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

func asCaller(r *http.Request, userID, email, name string) *http.Request {
	return r.WithContext(withCaller(r.Context(), &caller{UserID: userID, Email: email, Name: name}))
}

func jsonRequest(method, path, body string) *http.Request {
	return httptest.NewRequest(method, path, bytes.NewBufferString(body))
}

func decode[T any](t *testing.T, rec *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(rec.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	return v
}

func seedUser(t *testing.T, s *store.Stores, u domain.User) {
	t.Helper()
	if u.Status == "" {
		u.Status = domain.UserActive
	}
	if _, err := s.Users.CreateIfAbsent(context.Background(), u); err != nil {
		t.Fatalf("seed user %s: %v", u.UserID, err)
	}
}

func seedTeam(t *testing.T, s *store.Stores, teamID, name, admin string, status domain.TeamStatus, joined time.Time) {
	t.Helper()
	team := domain.Team{TeamID: teamID, Name: name, Status: status, CreatedBy: admin, CreatedAt: joined}
	if err := s.CreateTeamWithAdmin(context.Background(), team, domain.NewMembership(admin, teamID, domain.RoleAdmin, joined)); err != nil {
		t.Fatalf("seed team %s: %v", teamID, err)
	}
}

func seedInvite(t *testing.T, s *store.Stores, code, teamID, email, invitedBy string, status domain.InvitationStatus, expires time.Time) {
	t.Helper()
	inv := domain.Invitation{
		Code: code, TeamID: teamID, Email: email, Status: status, InvitedBy: invitedBy,
		CreatedAt: expires.Add(-14 * 24 * time.Hour), ExpiresAt: expires.Unix(),
	}
	if err := s.Invitations.Create(context.Background(), inv); err != nil {
		t.Fatalf("seed invite %s: %v", code, err)
	}
}
