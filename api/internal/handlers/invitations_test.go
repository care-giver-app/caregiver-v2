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

func TestInvitations_mineAndAccept(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()

	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "Group", CreatedBy: "u1", CreatedAt: now},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "tok-1", CareGroupID: "g1", Email: "invitee@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})

	mine := handlers.NewInvitations(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/invitations/mine", nil), "u2", "invitee@x.com", nil)
	rec := httptest.NewRecorder()
	mine.Mine(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("mine code=%d", rec.Code)
	}
	var list []struct {
		Token         string `json:"token"`
		CareGroupName string `json:"care_group_name"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &list)
	if len(list) != 1 || list[0].Token != "tok-1" || list[0].CareGroupName != "Group" {
		t.Fatalf("unexpected mine: %s", rec.Body.String())
	}

	areq := httptest.NewRequest(http.MethodPost, "/invitations/tok-1/accept", nil)
	areq.SetPathValue("token", "tok-1")
	areq = withAuth(areq, "u2", "invitee@x.com", nil)
	arec := httptest.NewRecorder()
	mine.Accept(arec, areq)
	if arec.Code != http.StatusOK {
		t.Fatalf("accept code=%d body=%s", arec.Code, arec.Body.String())
	}
	if m, err := s.Memberships.Get(ctx, "u2", "g1"); err != nil || m.Role != domain.RoleCaregiver {
		t.Fatalf("membership not created: %+v err=%v", m, err)
	}

	arec2 := httptest.NewRecorder()
	areq2 := httptest.NewRequest(http.MethodPost, "/invitations/tok-1/accept", nil)
	areq2.SetPathValue("token", "tok-1")
	areq2 = withAuth(areq2, "u2", "invitee@x.com", nil)
	mine.Accept(arec2, areq2)
	if arec2.Code != http.StatusOK {
		t.Fatalf("re-accept should be idempotent, got %d", arec2.Code)
	}
}

func TestInvitations_acceptExpired410(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	past := time.Now().Add(-time.Hour).UTC()
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "old", CareGroupID: "g1", Email: "x@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: past, ExpiresAt: past.Unix(),
	})
	h := handlers.NewInvitations(s)
	req := httptest.NewRequest(http.MethodPost, "/invitations/old/accept", nil)
	req.SetPathValue("token", "old")
	req = withAuth(req, "u2", "x@x.com", nil)
	rec := httptest.NewRecorder()
	h.Accept(rec, req)
	if rec.Code != http.StatusGone {
		t.Fatalf("want 410, got %d", rec.Code)
	}
}
