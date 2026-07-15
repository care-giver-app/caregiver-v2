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

// Isolation: a user who is admin of their own group must not touch another group.

func TestIsolation_nonMemberCannotInvite(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "A", CreatedBy: "userA", CreatedAt: now},
		domain.Membership{UserID: "userA", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})

	cg := handlers.NewCareGroups(s)
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"z@z.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "userB", "userB@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	cg.CreateInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("stranger invite should be 403, got %d", rec.Code)
	}
}

func TestIsolation_zeroMembershipSeesNothing(t *testing.T) {
	s := dynamotest.Start(t)
	_, _ = s.Users.CreateIfAbsent(context.Background(), domain.User{UserID: "lonely", Email: "l@x.com", Name: "L", CreatedAt: time.Now().UTC()})
	me := handlers.NewMe(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/me", nil), "lonely", "l@x.com", nil)
	rec := httptest.NewRecorder()
	me.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"memberships":[]`) {
		t.Fatalf("zero-membership user should see empty memberships: %s", rec.Body.String())
	}
}

func TestIsolation_caregiverCannotInvite(t *testing.T) {
	s := dynamotest.Start(t)
	cg := handlers.NewCareGroups(s)
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"z@z.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u3", "u3@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	cg.CreateInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver invite should be 403, got %d", rec.Code)
	}
}

func TestIsolation_strangerCannotRevoke(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "tokA", CareGroupID: "g1", Email: "p@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "userA", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})
	cg := handlers.NewCareGroups(s)
	req := httptest.NewRequest(http.MethodDelete, "/care-groups/g1/invitations/tokA", nil)
	req.SetPathValue("careGroupId", "g1")
	req.SetPathValue("token", "tokA")
	req = withAuth(req, "userB", "userB@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	cg.RevokeInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("stranger revoke should be 403, got %d", rec.Code)
	}
	if inv, _ := s.Invitations.Get(ctx, "tokA"); inv.Status != domain.InvitePending {
		t.Fatalf("invite should remain pending, got %s", inv.Status)
	}
}

func TestIsolation_nonMemberCannotReadReceiver(t *testing.T) {
	s := dynamotest.Start(t)
	_ = s.Receivers.Put(context.Background(), domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewReceivers(s)
	req := httptest.NewRequest(http.MethodGet, "/receivers/r1", nil)
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member receiver read should be 403, got %d", rec.Code)
	}
}

func TestIsolation_nonMemberCannotLogEvent(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers) // tr1 in g1
	h := handlers.NewEvents(s)
	req := httptest.NewRequest(http.MethodPost, "/trackers/tr1/events", strings.NewReader(`{"values":{"systolic":120}}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member event log should be 403, got %d", rec.Code)
	}
}

func TestIsolation_nonMemberCannotCreateScheduledItem(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers) // tr1 in g1
	h := handlers.NewScheduledItems(s)
	req := httptest.NewRequest(http.MethodPost, "/trackers/tr1/scheduled-items", strings.NewReader(`{"scheduled_for":"2026-08-01T10:00:00Z"}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member scheduled item create should be 403, got %d", rec.Code)
	}
}

func TestIsolation_nonMemberCannotReadScheduledItem(t *testing.T) {
	s := dynamotest.Start(t)
	now := time.Now().UTC()
	_ = s.ScheduledItems.Put(context.Background(), domain.ScheduledItem{
		ScheduledItemID: "si1", TrackerID: "tr1", CareGroupID: "g1", ReceiverID: "r1",
		Values: map[string]any{}, ScheduledFor: now.Add(24 * time.Hour), CreatedBy: "u1", CreatedAt: now,
	})
	h := handlers.NewScheduledItems(s)
	req := httptest.NewRequest(http.MethodGet, "/scheduled-items/si1", nil)
	req.SetPathValue("scheduledItemId", "si1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member scheduled item read should be 403, got %d", rec.Code)
	}
}

func TestIsolation_caregiverCannotCreateTracker(t *testing.T) {
	s := dynamotest.Start(t)
	_ = s.Receivers.Put(context.Background(), domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewTrackers(s)
	req := httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers",
		strings.NewReader(`{"name":"W","kind":"measurement","fields":[{"key":"w","label":"W","type":"number"}]}`))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver tracker create should be 403, got %d", rec.Code)
	}
}
