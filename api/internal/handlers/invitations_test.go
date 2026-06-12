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

func TestInvitations_adminInviteRequiresEmailMatch(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "adm", CareGroupID: "g1", Email: "invited@x.com", Role: domain.RoleAdmin,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})
	h := handlers.NewInvitations(s)

	// wrong email -> 403, no membership created
	req := httptest.NewRequest(http.MethodPost, "/invitations/adm/accept", nil)
	req.SetPathValue("token", "adm")
	req = withAuth(req, "mallory", "mallory@x.com", nil)
	rec := httptest.NewRecorder()
	h.Accept(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("admin accept with wrong email should be 403, got %d", rec.Code)
	}
	if _, err := s.Memberships.Get(ctx, "mallory", "g1"); err == nil {
		t.Fatal("mallory must not have become a member")
	}

	// matching email -> 200, admin membership created
	req2 := httptest.NewRequest(http.MethodPost, "/invitations/adm/accept", nil)
	req2.SetPathValue("token", "adm")
	req2 = withAuth(req2, "invitee", "invited@x.com", nil)
	rec2 := httptest.NewRecorder()
	h.Accept(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("admin accept with matching email should be 200, got %d body=%s", rec2.Code, rec2.Body.String())
	}
	if m, err := s.Memberships.Get(ctx, "invitee", "g1"); err != nil || m.Role != domain.RoleAdmin {
		t.Fatalf("invitee should be admin: %+v err=%v", m, err)
	}
}

func TestInvitations_caregiverInviteStaysTokenFirst(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "cg", CareGroupID: "g1", Email: "invited@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})
	h := handlers.NewInvitations(s)
	// non-matching email still accepted for caregiver invites
	req := httptest.NewRequest(http.MethodPost, "/invitations/cg/accept", nil)
	req.SetPathValue("token", "cg")
	req = withAuth(req, "someone", "different@x.com", nil)
	rec := httptest.NewRecorder()
	h.Accept(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("caregiver accept should be token-first 200, got %d", rec.Code)
	}
}

func TestInvitations_acceptDoesNotOverwriteExistingMembership(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	// user is already ADMIN of g1
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "G", CreatedBy: "u1", CreatedAt: now},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})
	// a pending CAREGIVER invite for the same group, token-first
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "t", CareGroupID: "g1", Email: "u1@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})
	h := handlers.NewInvitations(s)
	req := httptest.NewRequest(http.MethodPost, "/invitations/t/accept", nil)
	req.SetPathValue("token", "t")
	req = withAuth(req, "u1", "u1@x.com", nil)
	rec := httptest.NewRecorder()
	h.Accept(rec, req)
	// idempotent-ish success, but role must remain admin (not overwritten to caregiver)
	if m, err := s.Memberships.Get(ctx, "u1", "g1"); err != nil || m.Role != domain.RoleAdmin {
		t.Fatalf("existing admin role must be preserved: %+v err=%v (resp code=%d)", m, err, rec.Code)
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
