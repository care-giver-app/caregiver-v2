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

func TestTrackers_createResolvesGroupAndRequiresAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_ = s.Receivers.Put(ctx, domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewTrackers(s)

	body := `{"name":"Weight","kind":"measurement","fields":[{"key":"weight","label":"Weight","type":"number","required":true}]}`

	// caregiver -> 403
	req := httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers", strings.NewReader(body))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver tracker create should be 403, got %d", rec.Code)
	}

	// admin -> 201
	req = httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers", strings.NewReader(body))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec = httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("admin tracker create should be 201, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"care_group_id":"g1"`) {
		t.Fatalf("tracker should denormalize care_group_id, got %s", rec.Body.String())
	}
}

func TestTrackers_createRejectsBadKind(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_ = s.Receivers.Put(ctx, domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewTrackers(s)
	req := httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers",
		strings.NewReader(`{"name":"X","kind":"bogus","fields":[]}`))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("bad kind should be 400, got %d", rec.Code)
	}
}
