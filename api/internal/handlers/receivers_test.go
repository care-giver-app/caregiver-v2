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

func TestReceivers_createRequiresAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewReceivers(s)

	// caregiver -> 403
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/receivers", strings.NewReader(`{"name":"Mom"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver create should be 403, got %d", rec.Code)
	}

	// admin -> 201
	req = httptest.NewRequest(http.MethodPost, "/care-groups/g1/receivers", strings.NewReader(`{"name":"Mom"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec = httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("admin create should be 201, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"name":"Mom"`) {
		t.Fatalf("expected receiver body, got %s", rec.Body.String())
	}
}

func TestReceivers_getMemberGated(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_ = s.Receivers.Put(ctx, domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewReceivers(s)

	// non-member -> 403
	req := httptest.NewRequest(http.MethodGet, "/receivers/r1", nil)
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member get should be 403, got %d", rec.Code)
	}

	// member -> 200
	req = httptest.NewRequest(http.MethodGet, "/receivers/r1", nil)
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec = httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("member get should be 200, got %d", rec.Code)
	}
}
