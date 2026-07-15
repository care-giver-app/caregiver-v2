package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestScheduledItemStore_CRUDAndList(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	base := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)

	mk := func(id string, offset time.Duration) domain.ScheduledItem {
		return domain.ScheduledItem{
			ScheduledItemID: id, TrackerID: "trk1", CareGroupID: "cg1", ReceiverID: "rcv1",
			Values: map[string]any{}, ScheduledFor: base.Add(offset), CreatedBy: "u1", CreatedAt: base,
		}
	}
	if err := s.ScheduledItems.Put(ctx, mk("si2", 48*time.Hour)); err != nil {
		t.Fatalf("put si2: %v", err)
	}
	if err := s.ScheduledItems.Put(ctx, mk("si1", 24*time.Hour)); err != nil {
		t.Fatalf("put si1: %v", err)
	}

	got, err := s.ScheduledItems.Get(ctx, "si1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.TrackerID != "trk1" || got.CareGroupID != "cg1" {
		t.Fatalf("unexpected item: %+v", got)
	}

	if _, err := s.ScheduledItems.Get(ctx, "missing"); err != store.ErrNotFound {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	byTracker, _, err := s.ScheduledItems.ListByTracker(ctx, "trk1", 10, "", nil, nil)
	if err != nil {
		t.Fatalf("list by tracker: %v", err)
	}
	if len(byTracker) != 2 || byTracker[0].ScheduledItemID != "si1" {
		t.Fatalf("want soonest-first [si1, si2], got %+v", byTracker)
	}

	byReceiver, _, err := s.ScheduledItems.ListByReceiver(ctx, "rcv1", 10, "", nil, nil)
	if err != nil {
		t.Fatalf("list by receiver: %v", err)
	}
	if len(byReceiver) != 2 {
		t.Fatalf("want 2 by receiver, got %d", len(byReceiver))
	}

	if err := s.ScheduledItems.Delete(ctx, "si1"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.ScheduledItems.Get(ctx, "si1"); err != store.ErrNotFound {
		t.Fatalf("want ErrNotFound after delete, got %v", err)
	}
}
