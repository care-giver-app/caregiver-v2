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

func TestAuthenticator_emailFollowsTheToken(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	seedUser(t, s, domain.User{UserID: "sub-1", Email: "old@x.com", Name: "Sam"})
	var seen *caller
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { seen = callerFrom(r.Context()) })
	serve := func(c claims) {
		a := NewAuthenticator(s)
		a.extract = func(*http.Request) (claims, bool) { return c, true }
		seen = nil
		a.Wrap(next).ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v1/me", nil))
	}
	email := func() string {
		u, err := s.Users.Get(ctx, "sub-1")
		if err != nil {
			t.Fatal(err)
		}
		return u.Email
	}

	serve(claims{Sub: "sub-1", Email: "New@X.com", EmailVerified: "false"})
	if email() != "old@x.com" {
		t.Fatal("an unverified address must not be copied")
	}
	serve(claims{Sub: "sub-1", Email: ""})
	if email() != "old@x.com" {
		t.Fatal("a token without an address must not clear it")
	}
	serve(claims{Sub: "sub-1", Email: " New@X.com ", EmailVerified: "true"})
	if email() != "new@x.com" || seen.Email != "new@x.com" || seen.Name != "Sam" {
		t.Fatalf("row=%q caller=%+v", email(), seen)
	}
	// A token without the claim at all is taken as the provider's address.
	serve(claims{Sub: "sub-1", Email: "third@x.com"})
	if email() != "third@x.com" {
		t.Fatalf("row=%q", email())
	}
	if ids, _ := s.Users.IDsByEmail(ctx, "third@x.com"); len(ids) != 1 {
		t.Fatalf("the email-index follows: %v", ids)
	}
}

func TestAuthenticator_WrapClosing(t *testing.T) {
	s := dynamotest.Start(t)
	closedAt := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	seedUser(t, s, domain.User{UserID: "sub-closed", Status: domain.UserClosed, ClosedAt: &closedAt, CreatedAt: closedAt})
	seedUser(t, s, domain.User{UserID: "sub-open", Email: "o@x.com", Name: "O"})
	var seen *caller
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { seen = callerFrom(r.Context()) })
	serve := func(sub string, closing bool) int {
		a := NewAuthenticator(s)
		a.extract = func(*http.Request) (claims, bool) { return claims{Sub: sub, Email: "c@x.com"}, true }
		seen = nil
		rec := httptest.NewRecorder()
		h := a.Wrap(next)
		if closing {
			h = a.WrapClosing(next)
		}
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/me/close", nil))
		return rec.Code
	}
	if code := serve("sub-closed", false); code != http.StatusUnauthorized {
		t.Fatalf("Wrap: %d", code)
	}
	if code := serve("sub-closed", true); code != http.StatusOK || seen == nil || !seen.Closed {
		t.Fatalf("WrapClosing: %d %+v", code, seen)
	}
	if u, _ := s.Users.Get(context.Background(), "sub-closed"); u.Email != "" {
		t.Fatalf("a closed row never takes an address back: %+v", u)
	}
	if code := serve("sub-open", true); code != http.StatusOK || seen.Closed {
		t.Fatalf("open account: %d %+v", code, seen)
	}
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
