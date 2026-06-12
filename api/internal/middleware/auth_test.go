package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestAuthenticator_JITProvisionsAndAttachesContext(t *testing.T) {
	stores := dynamotest.Start(t)
	a := NewAuthenticator(stores)
	a.extract = func(r *http.Request) (claims, bool) {
		return claims{Sub: "sub-1", Email: "New@X.com", Name: "New"}, true
	}

	var seen *auth.AuthContext
	h := a.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = auth.FromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/me", nil))
	if rec.Code != http.StatusOK || seen == nil || seen.UserID != "sub-1" {
		t.Fatalf("first: code=%d ctx=%+v", rec.Code, seen)
	}
	if seen.Email != "new@x.com" {
		t.Fatalf("email should be normalized, got %q", seen.Email)
	}
	if u, err := stores.Users.Get(context.Background(), "sub-1"); err != nil || u.Name != "New" {
		t.Fatalf("user not provisioned: %+v err=%v", u, err)
	}

	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, httptest.NewRequest(http.MethodGet, "/me", nil))
	if rec2.Code != http.StatusOK {
		t.Fatalf("second: code=%d", rec2.Code)
	}
}

func TestAuthenticator_MissingClaims401(t *testing.T) {
	stores := dynamotest.Start(t)
	a := NewAuthenticator(stores)
	a.extract = func(r *http.Request) (claims, bool) { return claims{}, false }
	h := a.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/me", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}
