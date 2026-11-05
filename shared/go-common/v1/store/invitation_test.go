package store_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func invite(code, email string, status domain.InvitationStatus, now time.Time, ttl time.Duration) domain.Invitation {
	return domain.Invitation{
		Code: code, TeamID: "t1", Email: email, Status: status, InvitedBy: "u1",
		CreatedAt: now, ExpiresAt: now.Add(ttl).Unix(),
	}
}

func TestInvitation_CreateGetListPending(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	for _, inv := range []domain.Invitation{
		invite("c-pending", "invitee@x.com", domain.InvitePending, now, time.Hour),
		invite("c-accepted", "invitee@x.com", domain.InviteAccepted, now, time.Hour),
		invite("c-revoked", "invitee@x.com", domain.InviteRevoked, now, time.Hour),
		invite("c-other", "other@x.com", domain.InvitePending, now, time.Hour),
	} {
		if err := s.Invitations.Create(ctx, inv); err != nil {
			t.Fatalf("create %s: %v", inv.Code, err)
		}
	}

	var ccf *types.ConditionalCheckFailedException
	if err := s.Invitations.Create(ctx, invite("c-pending", "dup@x.com", domain.InvitePending, now, time.Hour)); !errors.As(err, &ccf) {
		t.Fatalf("duplicate code should fail the condition, got %v", err)
	}

	got, err := s.Invitations.Get(ctx, "c-pending")
	if err != nil || got.Email != "invitee@x.com" || got.TeamID != "t1" || got.ExpiresAt != now.Add(time.Hour).Unix() || !got.CreatedAt.Equal(now) {
		t.Fatalf("get: %+v err=%v", got, err)
	}
	if _, err := s.Invitations.Get(ctx, "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	pending, err := s.Invitations.ListPendingByEmail(ctx, "invitee@x.com")
	if err != nil || len(pending) != 1 || pending[0].Code != "c-pending" {
		t.Fatalf("ListPendingByEmail: %+v err=%v", pending, err)
	}
}

func TestRedeemInvitation_success(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.Invitations.Create(ctx, invite("c1", "invitee@x.com", domain.InvitePending, now, time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}

	m := domain.NewMembership("u2", "t1", domain.RoleCaregiver, now)
	if err := s.RedeemInvitation(ctx, "c1", m, now); err != nil {
		t.Fatalf("redeem: %v", err)
	}

	if inv, _ := s.Invitations.Get(ctx, "c1"); inv.Status != domain.InviteAccepted {
		t.Fatalf("status = %q, want accepted", inv.Status)
	}
	got, err := s.Memberships.Get(ctx, "u2", "t1")
	if err != nil || got.Role != domain.RoleCaregiver ||
		!got.NotifyReminders || !got.NotifyRangeAlerts || !got.NotifyGapAlerts || !got.NotifyUnrecordedAlerts {
		t.Fatalf("membership: %+v err=%v", got, err)
	}

	// Redeeming the now-accepted code again is not valid.
	other := domain.NewMembership("u3", "t1", domain.RoleCaregiver, now)
	if err := s.RedeemInvitation(ctx, "c1", other, now); !errors.Is(err, store.ErrInvitationNotValid) {
		t.Fatalf("accepted code: want ErrInvitationNotValid, got %v", err)
	}
	if _, err := s.Memberships.Get(ctx, "u3", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("no membership should be written, got %v", err)
	}
}

func TestRedeemInvitation_notValid(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)
	m := domain.NewMembership("u2", "t1", domain.RoleCaregiver, now)

	// Expired but still present (TTL deletion lags).
	if err := s.Invitations.Create(ctx, invite("c-expired", "a@x.com", domain.InvitePending, now, -time.Minute)); err != nil {
		t.Fatalf("create: %v", err)
	}
	// Exactly at expiry counts as expired.
	if err := s.Invitations.Create(ctx, invite("c-edge", "a@x.com", domain.InvitePending, now, 0)); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := s.Invitations.Create(ctx, invite("c-revoked", "a@x.com", domain.InviteRevoked, now, time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}

	for _, code := range []string{"c-expired", "c-edge", "c-revoked", "c-missing"} {
		if err := s.RedeemInvitation(ctx, code, m, now); !errors.Is(err, store.ErrInvitationNotValid) {
			t.Fatalf("%s: want ErrInvitationNotValid, got %v", code, err)
		}
	}
	if _, err := s.Memberships.Get(ctx, "u2", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("no membership should be written, got %v", err)
	}
	if _, err := s.Invitations.Get(ctx, "c-missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("redeeming a missing code must not create it, got %v", err)
	}
	if inv, _ := s.Invitations.Get(ctx, "c-expired"); inv.Status != domain.InvitePending {
		t.Fatalf("expired invitation status = %q, want pending", inv.Status)
	}
}

func TestRedeemInvitation_alreadyMember(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	team := domain.Team{TeamID: "t1", Name: "T", Status: domain.TeamActive, CreatedBy: "u1", CreatedAt: now}
	if err := s.CreateTeamWithAdmin(ctx, team, domain.NewMembership("u1", "t1", domain.RoleAdmin, now)); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if err := s.Invitations.Create(ctx, invite("c1", "u1@x.com", domain.InvitePending, now, time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}

	err := s.RedeemInvitation(ctx, "c1", domain.NewMembership("u1", "t1", domain.RoleCaregiver, now), now)
	if !errors.Is(err, store.ErrAlreadyMember) {
		t.Fatalf("want ErrAlreadyMember, got %v", err)
	}
	if inv, _ := s.Invitations.Get(ctx, "c1"); inv.Status != domain.InvitePending {
		t.Fatalf("invitation should still be pending, got %q", inv.Status)
	}
	if m, _ := s.Memberships.Get(ctx, "u1", "t1"); m.Role != domain.RoleAdmin {
		t.Fatalf("existing membership should be untouched, got %+v", m)
	}
}

func TestRedeemInvitation_concurrentExactlyOneWins(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.Invitations.Create(ctx, invite("c1", "invitee@x.com", domain.InvitePending, now, time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}

	users := []string{"u2", "u3"}
	errs := make([]error, len(users))
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i, u := range users {
		wg.Add(1)
		go func(i int, u string) {
			defer wg.Done()
			<-start
			errs[i] = s.RedeemInvitation(ctx, "c1", domain.NewMembership(u, "t1", domain.RoleCaregiver, now), now)
		}(i, u)
	}
	close(start)
	wg.Wait()

	wins := 0
	for i, err := range errs {
		if err == nil {
			wins++
			continue
		}
		t.Logf("%s lost: %v", users[i], err)
	}
	if wins != 1 {
		t.Fatalf("want exactly one winner, got %d (errs=%v)", wins, errs)
	}

	members := 0
	for _, u := range users {
		if _, err := s.Memberships.Get(ctx, u, "t1"); err == nil {
			members++
		}
	}
	if members != 1 {
		t.Fatalf("want exactly one membership, got %d", members)
	}
}
