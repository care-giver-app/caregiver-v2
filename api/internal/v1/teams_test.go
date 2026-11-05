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

func TestTeams_Create(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)
	h := NewTeams(s)
	h.now = func() time.Time { return now }
	n := 0
	h.newID = func() string { n++; return "team-" + string(rune('0'+n)) }

	post := func(body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.Create(rec, asCaller(jsonRequest(http.MethodPost, "/v1/teams", body), "u1", "u1@x.com", "U1"))
		return rec
	}

	t.Run("creates team and admin membership", func(t *testing.T) {
		rec := post(`{"name":"  The Smiths  "}`)
		if rec.Code != http.StatusCreated {
			t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
		}
		got := decode[teamMembership](t, rec)
		if got != (teamMembership{TeamID: "team-1", Name: "The Smiths", Role: "admin"}) {
			t.Fatalf("unexpected: %+v", got)
		}
		team, err := s.Teams.Get(ctx, "team-1")
		if err != nil || team.Name != "The Smiths" || team.Status != domain.TeamActive ||
			team.CreatedBy != "u1" || !team.CreatedAt.Equal(now) {
			t.Fatalf("team = %+v err=%v", team, err)
		}
		m, err := s.Memberships.Get(ctx, "u1", "team-1")
		if err != nil || m.Role != domain.RoleAdmin || !m.JoinedAt.Equal(now) ||
			!m.NotifyReminders || !m.NotifyRangeAlerts || !m.NotifyGapAlerts || !m.NotifyUnrecordedAlerts {
			t.Fatalf("membership = %+v err=%v", m, err)
		}
	})

	t.Run("100 runes is allowed", func(t *testing.T) {
		if rec := post(`{"name":"` + strings.Repeat("é", 100) + `"}`); rec.Code != http.StatusCreated {
			t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
		}
	})

	for name, body := range map[string]string{
		"empty":           `{"name":""}`,
		"missing":         `{}`,
		"whitespace only": `{"name":"   \t "}`,
		"101 runes":       `{"name":"` + strings.Repeat("é", 101) + `"}`,
		"malformed":       `{"name":`,
		"not an object":   `"x"`,
	} {
		t.Run(name+" is 400", func(t *testing.T) {
			if rec := post(body); rec.Code != http.StatusBadRequest {
				t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
			}
		})
	}
}
