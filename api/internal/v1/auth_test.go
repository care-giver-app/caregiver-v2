package v1

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestAuthenticator(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)

	var seen *caller
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = callerFrom(r.Context())
		w.WriteHeader(http.StatusOK)
	})
	serve := func(c claims, ok bool) int {
		a := NewAuthenticator(s)
		a.now = func() time.Time { return now }
		a.extract = func(*http.Request) (claims, bool) { return c, ok }
		seen = nil
		rec := httptest.NewRecorder()
		a.Wrap(next).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/me", nil))
		return rec.Code
	}

	t.Run("no claims is 401", func(t *testing.T) {
		if code := serve(claims{}, false); code != http.StatusUnauthorized || seen != nil {
			t.Fatalf("code=%d seen=%+v", code, seen)
		}
		if code := serve(claims{Email: "a@x.com"}, true); code != http.StatusUnauthorized {
			t.Fatalf("empty sub: code=%d", code)
		}
	})

	t.Run("first call provisions, second does not overwrite", func(t *testing.T) {
		if code := serve(claims{Sub: "sub-1", Email: " New@X.com ", Name: "New"}, true); code != http.StatusOK {
			t.Fatalf("first: code=%d", code)
		}
		if seen == nil || seen.UserID != "sub-1" || seen.Email != "new@x.com" || seen.Name != "New" {
			t.Fatalf("caller = %+v", seen)
		}
		u, err := s.Users.Get(ctx, "sub-1")
		if err != nil || u.Email != "new@x.com" || u.Name != "New" || !u.EmailNotifications ||
			u.Status != domain.UserActive || !u.CreatedAt.Equal(now) || u.ClosedAt != nil {
			t.Fatalf("provisioned user = %+v err=%v", u, err)
		}

		if code := serve(claims{Sub: "sub-1", Email: "new@x.com", Name: "Renamed"}, true); code != http.StatusOK {
			t.Fatalf("second: code=%d", code)
		}
		if seen.Name != "New" {
			t.Fatalf("caller name should come from the stored row, got %q", seen.Name)
		}
		if u, _ := s.Users.Get(ctx, "sub-1"); u.Name != "New" {
			t.Fatalf("stored name was clobbered: %+v", u)
		}
	})

	t.Run("closed user is 401", func(t *testing.T) {
		closedAt := now.Add(-time.Hour)
		seedUser(t, s, domain.User{UserID: "sub-closed", Status: domain.UserClosed, ClosedAt: &closedAt, CreatedAt: closedAt})
		if code := serve(claims{Sub: "sub-closed", Email: "c@x.com", Name: "C"}, true); code != http.StatusUnauthorized || seen != nil {
			t.Fatalf("code=%d seen=%+v", code, seen)
		}
		if u, _ := s.Users.Get(ctx, "sub-closed"); u.Status != domain.UserClosed || u.Email != "" {
			t.Fatalf("closed row must be left alone: %+v", u)
		}
	})
}

func TestClaimName(t *testing.T) {
	if got := claimName(map[string]string{"name": "N", "given_name": "G"}); got != "N" {
		t.Fatalf("got %q", got)
	}
	if got := claimName(map[string]string{"given_name": "G", "family_name": "F"}); got != "G F" {
		t.Fatalf("got %q", got)
	}
	if got := claimName(map[string]string{"given_name": "G"}); got != "G" {
		t.Fatalf("got %q", got)
	}
}
