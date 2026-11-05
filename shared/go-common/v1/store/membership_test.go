package store_test

import (
	"context"
	"errors"
	"sort"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestMembership_GetAndListByUser(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	seed := []struct {
		team, user string
		role       domain.Role
	}{
		{"t1", "u1", domain.RoleAdmin},
		{"t2", "u1", domain.RoleCaregiver},
		{"t3", "u2", domain.RoleAdmin},
	}
	for _, x := range seed {
		team := domain.Team{TeamID: x.team, Name: x.team, Status: domain.TeamActive, CreatedBy: x.user, CreatedAt: now}
		if err := s.CreateTeamWithAdmin(ctx, team, domain.NewMembership(x.user, x.team, x.role, now)); err != nil {
			t.Fatalf("seed: %v", err)
		}
	}

	m, err := s.Memberships.Get(ctx, "u1", "t2")
	if err != nil || m.Role != domain.RoleCaregiver || !m.JoinedAt.Equal(now) ||
		!m.NotifyReminders || !m.NotifyRangeAlerts || !m.NotifyGapAlerts || !m.NotifyUnrecordedAlerts {
		t.Fatalf("get: %+v err=%v", m, err)
	}
	if _, err := s.Memberships.Get(ctx, "u2", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	ms, err := s.Memberships.ListByUser(ctx, "u1")
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	var teams []string
	for _, m := range ms {
		teams = append(teams, m.TeamID)
	}
	sort.Strings(teams)
	if len(teams) != 2 || teams[0] != "t1" || teams[1] != "t2" {
		t.Fatalf("ListByUser(u1) = %v", teams)
	}

	if none, err := s.Memberships.ListByUser(ctx, "nobody"); err != nil || len(none) != 0 {
		t.Fatalf("ListByUser(nobody) = %+v err=%v", none, err)
	}
}
