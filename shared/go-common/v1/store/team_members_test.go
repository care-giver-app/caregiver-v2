package store_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

// teamOf seeds team t1 with the given members (user id → role).
func teamOf(t *testing.T, l dynamotest.Local, members map[string]domain.Role) {
	t.Helper()
	now := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	seed(t, l, l.Names.Teams, domain.Team{TeamID: "t1", Name: "Smiths", Status: domain.TeamActive, CreatedBy: "a", CreatedAt: now})
	for id, role := range members {
		seed(t, l, l.Names.Memberships, domain.NewMembership(id, "t1", role, now))
	}
}

func TestMembers_lastAdmin(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	s := l.Stores
	teamOf(t, l, map[string]domain.Role{"a": domain.RoleAdmin, "c": domain.RoleCaregiver})

	// The only admin can neither demote themselves, leave, nor be removed.
	if _, err := s.ChangeRole(ctx, "t1", "a", domain.RoleCaregiver); !errors.Is(err, store.ErrLastAdmin) {
		t.Fatalf("demote last admin: %v", err)
	}
	if err := s.RemoveMember(ctx, "t1", "a"); !errors.Is(err, store.ErrLastAdmin) {
		t.Fatalf("remove last admin: %v", err)
	}
	if m, _ := s.Memberships.Get(ctx, "a", "t1"); m.Role != domain.RoleAdmin {
		t.Fatalf("last admin changed: %+v", m)
	}

	// Unknown member.
	if _, err := s.ChangeRole(ctx, "t1", "nobody", domain.RoleAdmin); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("change unknown: %v", err)
	}
	if err := s.RemoveMember(ctx, "t1", "nobody"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("remove unknown: %v", err)
	}

	// Already in the role: returned unchanged.
	if m, err := s.ChangeRole(ctx, "t1", "a", domain.RoleAdmin); err != nil || m.Role != domain.RoleAdmin || !m.NotifyGapAlerts {
		t.Fatalf("no-op: %+v %v", m, err)
	}

	// With two admins, one may step down or leave.
	if m, err := s.ChangeRole(ctx, "t1", "c", domain.RoleAdmin); err != nil || m.Role != domain.RoleAdmin {
		t.Fatalf("promote: %+v %v", m, err)
	}
	if m, err := s.ChangeRole(ctx, "t1", "a", domain.RoleCaregiver); err != nil || m.Role != domain.RoleCaregiver {
		t.Fatalf("demote with another admin: %+v %v", m, err)
	}
	if err := s.RemoveMember(ctx, "t1", "c"); !errors.Is(err, store.ErrLastAdmin) {
		t.Fatalf("c is now the only admin: %v", err)
	}
	if err := s.RemoveMember(ctx, "t1", "a"); err != nil {
		t.Fatalf("remove caregiver: %v", err)
	}
	if _, err := s.Memberships.Get(ctx, "a", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("membership left behind: %v", err)
	}
}

func TestMembers_twoAdminsLeavingAtOnceLeaveOne(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	teamOf(t, l, map[string]domain.Role{"a": domain.RoleAdmin, "b": domain.RoleAdmin})

	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i, id := range []string{"a", "b"} {
		wg.Add(1)
		go func(i int, id string) {
			defer wg.Done()
			errs[i] = l.Stores.RemoveMember(ctx, "t1", id)
		}(i, id)
	}
	wg.Wait()
	ms, err := l.Stores.Memberships.ListByTeam(ctx, "t1")
	if err != nil {
		t.Fatal(err)
	}
	if len(ms) != 1 || ms[0].Role != domain.RoleAdmin {
		t.Fatalf("want exactly one admin left, got %+v (errs %v)", ms, errs)
	}
	refused := 0
	for _, err := range errs {
		if errors.Is(err, store.ErrLastAdmin) {
			refused++
		} else if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if refused != 1 {
		t.Fatalf("want one refusal, got errs %v", errs)
	}
}

func TestCloseTeam(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	s := l.Stores
	at := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	teamOf(t, l, map[string]domain.Role{"a": domain.RoleAdmin, "c": domain.RoleCaregiver})

	if err := s.CloseTeam(ctx, "t1", "a", at); !errors.Is(err, store.ErrNotLastCaregiver) {
		t.Fatalf("two members: %v", err)
	}
	if team, _ := s.Teams.Get(ctx, "t1"); team.Status != domain.TeamActive {
		t.Fatalf("closed anyway: %+v", team)
	}
	if err := s.RemoveMember(ctx, "t1", "c"); err != nil {
		t.Fatal(err)
	}
	if err := s.CloseTeam(ctx, "t1", "a", at); err != nil {
		t.Fatalf("close: %v", err)
	}
	team, _ := s.Teams.Get(ctx, "t1")
	if team.Status != domain.TeamArchived || team.ArchivedBy != "a" || team.ArchivedAt == nil || !team.ArchivedAt.Equal(at) {
		t.Fatalf("team: %+v", team)
	}
	if _, err := s.Memberships.Get(ctx, "a", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("membership kept: %v", err)
	}
	if err := s.CloseTeam(ctx, "t1", "a", at); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("closing again: %v", err)
	}
}

func TestMemberships_ListByTeamAndNotifications(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	teamOf(t, l, map[string]domain.Role{"a": domain.RoleAdmin, "c": domain.RoleCaregiver})
	seed(t, l, l.Names.Memberships, domain.NewMembership("a", "t2", domain.RoleAdmin, time.Now()))

	ms, err := l.Stores.Memberships.ListByTeam(ctx, "t1")
	if err != nil || len(ms) != 2 {
		t.Fatalf("list: %+v %v", ms, err)
	}

	m, err := l.Stores.Memberships.SetNotifications(ctx, "c", "t1", store.NotificationChoices{Reminders: true, GapAlerts: true})
	if err != nil || !m.NotifyReminders || m.NotifyRangeAlerts || !m.NotifyGapAlerts || m.NotifyUnrecordedAlerts || m.Role != domain.RoleCaregiver {
		t.Fatalf("set: %+v %v", m, err)
	}
	// Nobody else's choices move.
	if other, _ := l.Stores.Memberships.Get(ctx, "a", "t1"); !other.NotifyRangeAlerts || !other.NotifyUnrecordedAlerts {
		t.Fatalf("other member changed: %+v", other)
	}
	if _, err := l.Stores.Memberships.SetNotifications(ctx, "nobody", "t1", store.NotificationChoices{}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("non-member: %v", err)
	}
	if _, err := l.Stores.Memberships.Get(ctx, "nobody", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("update created a row: %v", err)
	}
}
