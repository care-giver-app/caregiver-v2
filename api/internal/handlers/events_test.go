package handlers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func seedTracker(t *testing.T, s interface {
	Put(context.Context, domain.Tracker) error
}) {
	t.Helper()
	max140 := 140.0
	tr := domain.Tracker{
		TrackerID: "tr1", ReceiverID: "r1", CareGroupID: "g1", Name: "BP",
		Kind: domain.KindMeasurement, CreatedAt: time.Now().UTC(),
		Fields: []domain.Field{
			{Key: "systolic", Label: "Systolic", Type: domain.FieldNumber, Required: true, Threshold: &domain.Threshold{Max: &max140}},
		},
	}
	if err := s.Put(context.Background(), tr); err != nil {
		t.Fatalf("seed tracker: %v", err)
	}
}

func TestEvents_logValidatesAndDenormalizes(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers)
	h := handlers.NewEvents(s)

	// invalid: missing required systolic -> 400
	req := httptest.NewRequest(http.MethodPost, "/trackers/tr1/events", strings.NewReader(`{"values":{}}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("missing required should be 400, got %d", rec.Code)
	}

	// valid -> 201, denormalized receiver/group, logged_by set
	req = httptest.NewRequest(http.MethodPost, "/trackers/tr1/events", strings.NewReader(`{"values":{"systolic":128}}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec = httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("valid log should be 201, got %d: %s", rec.Code, rec.Body.String())
	}
	for _, want := range []string{`"receiver_id":"r1"`, `"care_group_id":"g1"`, `"logged_by":"u1"`} {
		if !strings.Contains(rec.Body.String(), want) {
			t.Fatalf("expected %s in %s", want, rec.Body.String())
		}
	}
}

func TestEvents_listReturnsBreaches(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers)
	h := handlers.NewEvents(s)
	_ = s.Events.Put(context.Background(), domain.Event{
		TrackerID: "tr1", EventID: "e1", CareGroupID: "g1", ReceiverID: "r1",
		Values: map[string]any{"systolic": 162.0}, OccurredAt: time.Now().UTC(), LoggedBy: "u1", CreatedAt: time.Now().UTC(),
	})
	req := httptest.NewRequest(http.MethodGet, "/trackers/tr1/events", nil)
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.List(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"bound":"max"`) {
		t.Fatalf("expected breach in list body, got %d %s", rec.Code, rec.Body.String())
	}
}
