package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestInvitation_createListAccept(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	inv := domain.Invitation{
		Token: "tok-1", CareGroupID: "g1", Email: "invitee@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	}
	if err := s.Invitations.Create(ctx, inv); err != nil {
		t.Fatalf("create: %v", err)
	}

	byEmail, err := s.Invitations.ListPendingByEmail(ctx, "invitee@x.com")
	if err != nil || len(byEmail) != 1 {
		t.Fatalf("ListPendingByEmail: %+v err=%v", byEmail, err)
	}

	mem := domain.Membership{UserID: "u2", CareGroupID: "g1", Role: domain.RoleCaregiver, CreatedAt: now}
	if err := s.AcceptInvitation(ctx, "tok-1", mem); err != nil {
		t.Fatalf("accept: %v", err)
	}
	if m, err := s.Memberships.Get(ctx, "u2", "g1"); err != nil || m.Role != domain.RoleCaregiver {
		t.Fatalf("membership after accept: %+v err=%v", m, err)
	}

	err = s.AcceptInvitation(ctx, "tok-1", mem)
	if err == nil {
		t.Fatal("expected second accept to fail the pending condition")
	}

	byEmail, _ = s.Invitations.ListPendingByEmail(ctx, "invitee@x.com")
	if len(byEmail) != 0 {
		t.Fatalf("expected no pending invites, got %d", len(byEmail))
	}

	if _, err := s.Invitations.Get(ctx, "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
