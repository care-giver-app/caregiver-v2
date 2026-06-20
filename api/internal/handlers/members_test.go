package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestMembers_listsResolvedNames(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	_, _ = s.Users.CreateIfAbsent(ctx, domain.User{UserID: "u1", Email: "u1@x.com", Name: "Una", CreatedAt: now})
	_, _ = s.Users.CreateIfAbsent(ctx, domain.User{UserID: "u2", Email: "u2@x.com", Name: "Dos", CreatedAt: now})
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "Group One", CreatedBy: "u1", CreatedAt: now},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})
	_ = s.Memberships.Put(ctx, domain.Membership{UserID: "u2", CareGroupID: "g1", Role: domain.RoleCaregiver, CreatedAt: now})

	h := handlers.NewMembers(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/care-groups/g1/members", nil), "u1", "u1@x.com",
		map[string]domain.Role{"g1": domain.RoleAdmin})
	req.SetPathValue("careGroupId", "g1")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body []struct {
		UserID string `json:"user_id"`
		Name   string `json:"name"`
		Role   string `json:"role"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if len(body) != 2 {
		t.Fatalf("want 2 members, got %d: %s", len(body), rec.Body.String())
	}
	names := map[string]string{}
	for _, m := range body {
		names[m.UserID] = m.Name
	}
	if names["u1"] != "Una" || names["u2"] != "Dos" {
		t.Fatalf("unresolved names: %s", rec.Body.String())
	}
}

func TestMembers_nonMemberForbidden(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewMembers(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/care-groups/g1/members", nil), "stranger", "s@x.com", nil)
	req.SetPathValue("careGroupId", "g1")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d", rec.Code)
	}
}
