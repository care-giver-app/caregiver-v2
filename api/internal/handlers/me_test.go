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

func TestMe_returnsUserAndMemberships(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	_, _ = s.Users.CreateIfAbsent(ctx, domain.User{UserID: "u1", Email: "u1@x.com", Name: "U1", CreatedAt: now})
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "Group One", CreatedBy: "u1", CreatedAt: now},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})

	h := handlers.NewMe(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/me", nil), "u1", "u1@x.com",
		map[string]domain.Role{"g1": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body struct {
		User struct {
			UserID string `json:"user_id"`
			Email  string `json:"email"`
			Name   string `json:"name"`
		} `json:"user"`
		Memberships []struct {
			CareGroupID string `json:"care_group_id"`
			Name        string `json:"name"`
			Role        string `json:"role"`
		} `json:"memberships"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.User.UserID != "u1" || len(body.Memberships) != 1 ||
		body.Memberships[0].Name != "Group One" || body.Memberships[0].Role != "admin" {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}
