package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestMembership_createGroupAndQueries(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	g := domain.CareGroup{CareGroupID: "g1", Name: "One", CreatedBy: "u1", CreatedAt: now}
	admin := domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now}
	if err := s.CreateCareGroupWithAdmin(ctx, g, admin); err != nil {
		t.Fatalf("create group: %v", err)
	}
	if err := s.Memberships.Put(ctx, domain.Membership{UserID: "u2", CareGroupID: "g1", Role: domain.RoleCaregiver, CreatedAt: now}); err != nil {
		t.Fatalf("put member: %v", err)
	}

	byUser, err := s.Memberships.ListByUser(ctx, "u1")
	if err != nil || len(byUser) != 1 || byUser[0].Role != domain.RoleAdmin {
		t.Fatalf("ListByUser: %+v err=%v", byUser, err)
	}
	byGroup, err := s.Memberships.ListByGroup(ctx, "g1")
	if err != nil || len(byGroup) != 2 {
		t.Fatalf("ListByGroup: %+v err=%v", byGroup, err)
	}
}
