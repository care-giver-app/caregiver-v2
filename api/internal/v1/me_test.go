package v1

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestMe(t *testing.T) {
	s := dynamotest.Start(t)
	h := NewMe(s)
	get := func(userID string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, asCaller(httptest.NewRequest(http.MethodGet, "/v1/me", nil), userID, userID+"@x.com", "Name "+userID))
		return rec
	}

	t.Run("new user has empty teams array", func(t *testing.T) {
		rec := get("u-new")
		want := `{"caregiver":{"user_id":"u-new","email":"u-new@x.com","name":"Name u-new"},"teams":[]}`
		if rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != want {
			t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
		}
	})

	t.Run("teams in join order, archived omitted", func(t *testing.T) {
		base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
		// Joined later but created first, so order must come from joined_at.
		seedTeam(t, s, "t-a", "Later", "u1", domain.TeamActive, base.Add(2*time.Hour))
		seedTeam(t, s, "t-z", "Earlier", "u1", domain.TeamActive, base.Add(time.Hour))
		seedTeam(t, s, "t-arch", "Closed", "u1", domain.TeamArchived, base)

		rec := get("u1")
		if rec.Code != http.StatusOK {
			t.Fatalf("code=%d", rec.Code)
		}
		got := decode[myAccount](t, rec)
		if got.Caregiver.UserID != "u1" || len(got.Teams) != 2 ||
			got.Teams[0] != (teamMembership{TeamID: "t-z", Name: "Earlier", Role: "admin"}) ||
			got.Teams[1] != (teamMembership{TeamID: "t-a", Name: "Later", Role: "admin"}) {
			t.Fatalf("unexpected: %s", rec.Body.String())
		}
	})

	t.Run("no caller is 401", func(t *testing.T) {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/me", nil))
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("code=%d", rec.Code)
		}
	})
}
