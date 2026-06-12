package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestCareGroups_createMakesAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)

	req := withAuth(httptest.NewRequest(http.MethodPost, "/care-groups", strings.NewReader(`{"name":"Mom"}`)), "u1", "u1@x.com", nil)
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body struct {
		CareGroupID string `json:"care_group_id"`
		Name        string `json:"name"`
		Role        string `json:"role"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Role != "admin" || body.Name != "Mom" || body.CareGroupID == "" {
		t.Fatalf("unexpected: %s", rec.Body.String())
	}
	if m, err := s.Memberships.Get(context.Background(), "u1", body.CareGroupID); err != nil || m.Role != domain.RoleAdmin {
		t.Fatalf("admin membership not created: %+v err=%v", m, err)
	}
}

func TestCareGroups_createRejectsEmptyName(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)
	req := withAuth(httptest.NewRequest(http.MethodPost, "/care-groups", strings.NewReader(`{"name":"  "}`)), "u1", "u1@x.com", nil)
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestCareGroups_inviteRequiresAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)

	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"x@y.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u2", "u2@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.CreateInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d", rec.Code)
	}
}

func TestCareGroups_inviteSucceedsForAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)
	_ = s.CreateCareGroupWithAdmin(context.Background(),
		domain.CareGroup{CareGroupID: "g1", Name: "G", CreatedBy: "u1", CreatedAt: time.Now().UTC()},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: time.Now().UTC()})

	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"Invitee@X.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.CreateInvitation(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body struct {
		Token     string `json:"token"`
		Email     string `json:"email"`
		Role      string `json:"role"`
		ExpiresAt string `json:"expires_at"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Token == "" || body.Email != "invitee@x.com" || body.Role != "caregiver" {
		t.Fatalf("unexpected invite: %s", rec.Body.String())
	}
}
