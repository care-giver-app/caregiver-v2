package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestTeam_CreateWithAdmin_andBatchGet(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	for _, id := range []string{"t1", "t2"} {
		team := domain.Team{TeamID: id, Name: "Team " + id, Status: domain.TeamActive, CreatedBy: "u1", CreatedAt: now}
		if err := s.CreateTeamWithAdmin(ctx, team, domain.NewMembership("u1", id, domain.RoleAdmin, now)); err != nil {
			t.Fatalf("create %s: %v", id, err)
		}
	}

	got, err := s.Teams.Get(ctx, "t1")
	if err != nil || got.Name != "Team t1" || got.Status != domain.TeamActive || got.ArchivedAt != nil || got.ArchivedBy != "" {
		t.Fatalf("get: %+v err=%v", got, err)
	}
	if m, err := s.Memberships.Get(ctx, "u1", "t1"); err != nil || m.Role != domain.RoleAdmin || !m.NotifyGapAlerts {
		t.Fatalf("admin membership: %+v err=%v", m, err)
	}
	if _, err := s.Teams.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	byID, err := s.Teams.BatchGet(ctx, []string{"t1", "t2", "missing"})
	if err != nil {
		t.Fatalf("batchget: %v", err)
	}
	if len(byID) != 2 || byID["t1"].Name != "Team t1" || byID["t2"].Name != "Team t2" {
		t.Fatalf("unexpected: %+v", byID)
	}
}

func TestTeam_CreateWithAdmin_duplicateWritesNothing(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	first := domain.Team{TeamID: "t1", Name: "First", Status: domain.TeamActive, CreatedBy: "u1", CreatedAt: now}
	if err := s.CreateTeamWithAdmin(ctx, first, domain.NewMembership("u1", "t1", domain.RoleAdmin, now)); err != nil {
		t.Fatalf("create: %v", err)
	}

	dup := domain.Team{TeamID: "t1", Name: "Second", Status: domain.TeamActive, CreatedBy: "u2", CreatedAt: now}
	err := s.CreateTeamWithAdmin(ctx, dup, domain.NewMembership("u2", "t1", domain.RoleAdmin, now))
	var tce *types.TransactionCanceledException
	if !errors.As(err, &tce) {
		t.Fatalf("want TransactionCanceledException, got %v", err)
	}

	if got, _ := s.Teams.Get(ctx, "t1"); got.Name != "First" || got.CreatedBy != "u1" {
		t.Fatalf("team was overwritten: %+v", got)
	}
	if _, err := s.Memberships.Get(ctx, "u2", "t1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("membership should not be written, got %v", err)
	}
}
