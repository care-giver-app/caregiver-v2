package v1

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestInvitations_Mine(t *testing.T) {
	s := dynamotest.Start(t)
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)
	h := NewInvitations(s)
	h.now = func() time.Time { return now }

	seedUser(t, s, domain.User{UserID: "admin", Email: "admin@x.com", Name: "Ada", CreatedAt: now})
	closedAt := now.Add(-time.Hour)
	seedUser(t, s, domain.User{UserID: "closed", Status: domain.UserClosed, ClosedAt: &closedAt, CreatedAt: now})
	seedUser(t, s, domain.User{UserID: "nameless", Email: "nameless@x.com", CreatedAt: now})
	seedTeam(t, s, "t1", "Team One", "admin", domain.TeamActive, now)
	seedTeam(t, s, "t2", "Team Two", "admin", domain.TeamActive, now)
	seedTeam(t, s, "t-arch", "Archived", "admin", domain.TeamArchived, now)
	seedTeam(t, s, "t-mine", "Mine", "me", domain.TeamActive, now)

	const me = "me@x.com"
	seedInvite(t, s, "c-pending", "t1", me, "admin", domain.InvitePending, now.Add(3*24*time.Hour))
	seedInvite(t, s, "c-expired", "t1", me, "admin", domain.InvitePending, now.Add(-time.Minute))
	seedInvite(t, s, "c-edge", "t1", me, "admin", domain.InvitePending, now)
	seedInvite(t, s, "c-accepted", "t1", me, "admin", domain.InviteAccepted, now.Add(time.Hour))
	seedInvite(t, s, "c-revoked", "t1", me, "admin", domain.InviteRevoked, now.Add(time.Hour))
	seedInvite(t, s, "c-arch", "t-arch", me, "admin", domain.InvitePending, now.Add(time.Hour))
	seedInvite(t, s, "c-gone-team", "t-missing", me, "admin", domain.InvitePending, now.Add(time.Hour))
	seedInvite(t, s, "c-missing-inviter", "t2", me, "ghost", domain.InvitePending, now.Add(2*24*time.Hour))
	seedInvite(t, s, "c-closed-inviter", "t2", me, "closed", domain.InvitePending, now.Add(time.Hour))
	seedInvite(t, s, "c-nameless-inviter", "t2", me, "nameless", domain.InvitePending, now.Add(4*24*time.Hour))
	seedInvite(t, s, "c-member", "t-mine", me, "me", domain.InvitePending, now.Add(5*24*time.Hour))
	seedInvite(t, s, "c-other", "t1", "other@x.com", "admin", domain.InvitePending, now.Add(time.Hour))

	get := func(email string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.Mine(rec, asCaller(httptest.NewRequest(http.MethodGet, "/v1/me/invitations", nil), "me", email, "Me"))
		return rec
	}

	t.Run("lists live invitations ordered by expiry", func(t *testing.T) {
		// The authenticator normalizes the claims email; a mixed-case address
		// still matches because both sides are normalized.
		rec := get(domain.NormalizeEmail("  Me@X.COM "))
		if rec.Code != http.StatusOK {
			t.Fatalf("code=%d", rec.Code)
		}
		got := decode[[]invitationForMe](t, rec)
		want := []invitationForMe{
			{"c-closed-inviter", "t2", "Team Two", formerCaregiver, now.Add(time.Hour).Format(time.RFC3339)},
			{"c-missing-inviter", "t2", "Team Two", formerCaregiver, now.Add(2 * 24 * time.Hour).Format(time.RFC3339)},
			{"c-pending", "t1", "Team One", "Ada", "2026-11-08T12:00:00Z"},
			{"c-nameless-inviter", "t2", "Team Two", formerCaregiver, now.Add(4 * 24 * time.Hour).Format(time.RFC3339)},
			{"c-member", "t-mine", "Mine", "a former caregiver", now.Add(5 * 24 * time.Hour).Format(time.RFC3339)},
		}
		if len(got) != len(want) {
			t.Fatalf("got %d invitations: %s", len(got), rec.Body.String())
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("[%d] got %+v want %+v", i, got[i], want[i])
			}
		}
	})

	t.Run("no email or nothing pending is []", func(t *testing.T) {
		for _, email := range []string{"", "nobody@x.com"} {
			rec := get(email)
			if rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != "[]" {
				t.Fatalf("email %q: code=%d body=%s", email, rec.Code, rec.Body.String())
			}
		}
	})
}

func TestAuthenticatedMine_mixedCaseClaimsEmail(t *testing.T) {
	s := dynamotest.Start(t)
	now := time.Now().UTC()
	seedUser(t, s, domain.User{UserID: "admin", Email: "admin@x.com", Name: "Ada", CreatedAt: now})
	seedTeam(t, s, "t1", "Team One", "admin", domain.TeamActive, now)
	seedInvite(t, s, "c1", "t1", "invitee@x.com", "admin", domain.InvitePending, now.Add(time.Hour))

	a := NewAuthenticator(s)
	a.extract = func(*http.Request) (claims, bool) {
		return claims{Sub: "u2", Email: "InVitee@X.com", Name: "I"}, true
	}
	rec := httptest.NewRecorder()
	a.Wrap(http.HandlerFunc(NewInvitations(s).Mine)).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/me/invitations", nil))
	got := decode[[]invitationForMe](t, rec)
	if rec.Code != http.StatusOK || len(got) != 1 || got[0].Code != "c1" {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestInvitations_Redeem(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)
	h := NewInvitations(s)
	h.now = func() time.Time { return now }

	seedTeam(t, s, "t1", "Team One", "admin", domain.TeamActive, now)
	seedTeam(t, s, "t-arch", "Archived", "admin", domain.TeamArchived, now)
	seedInvite(t, s, "c-ok", "t1", "invitee@x.com", "admin", domain.InvitePending, now.Add(time.Hour))
	seedInvite(t, s, "c-expired", "t1", "invitee@x.com", "admin", domain.InvitePending, now.Add(-time.Minute))
	seedInvite(t, s, "c-accepted", "t1", "invitee@x.com", "admin", domain.InviteAccepted, now.Add(time.Hour))
	seedInvite(t, s, "c-revoked", "t1", "invitee@x.com", "admin", domain.InviteRevoked, now.Add(time.Hour))
	seedInvite(t, s, "c-arch", "t-arch", "invitee@x.com", "admin", domain.InvitePending, now.Add(time.Hour))
	seedInvite(t, s, "c-member", "t1", "admin@x.com", "admin", domain.InvitePending, now.Add(time.Hour))

	redeem := func(userID, email, body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.Redeem(rec, asCaller(jsonRequest(http.MethodPost, "/v1/invitations/redeem", body), userID, email, "N"))
		return rec
	}

	t.Run("success joins as caregiver, even from a different email", func(t *testing.T) {
		rec := redeem("u2", "relay@privaterelay.appleid.com", `{"code":"  c-ok  "}`)
		if rec.Code != http.StatusOK {
			t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
		}
		if got := decode[teamMembership](t, rec); got != (teamMembership{TeamID: "t1", Name: "Team One", Role: "caregiver"}) {
			t.Fatalf("unexpected: %+v", got)
		}
		m, err := s.Memberships.Get(ctx, "u2", "t1")
		if err != nil || m.Role != domain.RoleCaregiver || !m.JoinedAt.Equal(now) ||
			!m.NotifyReminders || !m.NotifyRangeAlerts || !m.NotifyGapAlerts || !m.NotifyUnrecordedAlerts {
			t.Fatalf("membership = %+v err=%v", m, err)
		}
		if inv, _ := s.Invitations.Get(ctx, "c-ok"); inv.Status != domain.InviteAccepted {
			t.Fatalf("status = %q", inv.Status)
		}
	})

	t.Run("every unredeemable code gets the identical 410", func(t *testing.T) {
		var first string
		for _, code := range []string{"c-unknown", "c-expired", "c-accepted", "c-revoked", "c-arch", "c-ok"} {
			rec := redeem("u3", "invitee@x.com", `{"code":"`+code+`"}`)
			if rec.Code != http.StatusGone {
				t.Fatalf("%s: code=%d body=%s", code, rec.Code, rec.Body.String())
			}
			if first == "" {
				first = rec.Body.String()
			} else if rec.Body.String() != first {
				t.Fatalf("%s: body %q differs from %q", code, rec.Body.String(), first)
			}
			if _, err := s.Memberships.Get(ctx, "u3", "t1"); err == nil {
				t.Fatalf("%s: membership should not exist", code)
			}
		}
		if strings.Contains(first, "expired") || strings.Contains(first, "revoked") {
			t.Fatalf("410 body leaks the reason: %s", first)
		}
	})

	t.Run("already a member is 409 and leaves the invitation pending", func(t *testing.T) {
		rec := redeem("admin", "admin@x.com", `{"code":"c-member"}`)
		if rec.Code != http.StatusConflict {
			t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
		}
		if inv, _ := s.Invitations.Get(ctx, "c-member"); inv.Status != domain.InvitePending {
			t.Fatalf("status = %q", inv.Status)
		}
		if m, _ := s.Memberships.Get(ctx, "admin", "t1"); m.Role != domain.RoleAdmin {
			t.Fatalf("existing membership changed: %+v", m)
		}
	})

	for name, body := range map[string]string{
		"empty code":      `{"code":""}`,
		"whitespace code": `{"code":"   "}`,
		"missing code":    `{}`,
		"malformed":       `{"code":`,
	} {
		t.Run(name+" is 400", func(t *testing.T) {
			if rec := redeem("u4", "x@x.com", body); rec.Code != http.StatusBadRequest {
				t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
			}
		})
	}
}
