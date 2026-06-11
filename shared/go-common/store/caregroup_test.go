package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestCareGroupStore_BatchGet(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()

	for _, g := range []domain.CareGroup{
		{CareGroupID: "g1", Name: "One", CreatedBy: "u1", CreatedAt: time.Now().UTC()},
		{CareGroupID: "g2", Name: "Two", CreatedBy: "u1", CreatedAt: time.Now().UTC()},
	} {
		m := domain.Membership{UserID: "u1", CareGroupID: g.CareGroupID, Role: domain.RoleAdmin, CreatedAt: time.Now().UTC()}
		if err := s.CreateCareGroupWithAdmin(ctx, g, m); err != nil {
			t.Fatalf("seed %s: %v", g.CareGroupID, err)
		}
	}

	got, err := s.CareGroups.BatchGet(ctx, []string{"g1", "g2", "missing"})
	if err != nil {
		t.Fatalf("batchget: %v", err)
	}
	if len(got) != 2 || got["g1"].Name != "One" || got["g2"].Name != "Two" {
		t.Fatalf("unexpected: %+v", got)
	}
}
