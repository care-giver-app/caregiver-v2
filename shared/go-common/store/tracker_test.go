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

func TestTrackerStore_putGetListArchive(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()

	tr := domain.Tracker{
		TrackerID: "tr1", ReceiverID: "r1", CareGroupID: "g1", Name: "Weight",
		Kind: domain.KindMeasurement, CreatedBy: "u1", CreatedAt: now,
		Fields: []domain.Field{{Key: "weight", Label: "Weight", Type: domain.FieldNumber, Required: true}},
	}
	if err := s.Trackers.Put(ctx, tr); err != nil {
		t.Fatalf("put: %v", err)
	}

	got, err := s.Trackers.Get(ctx, "tr1")
	if err != nil || got.Name != "Weight" || len(got.Fields) != 1 || got.Fields[0].Key != "weight" {
		t.Fatalf("get tr1: %+v err %v", got, err)
	}
	if _, err := s.Trackers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	list, err := s.Trackers.ListByReceiver(ctx, "r1")
	if err != nil || len(list) != 1 {
		t.Fatalf("list r1: %d err %v", len(list), err)
	}

	if err := s.Trackers.Archive(ctx, "tr1"); err != nil {
		t.Fatalf("archive: %v", err)
	}
	list, _ = s.Trackers.ListByReceiver(ctx, "r1")
	if len(list) != 0 {
		t.Fatalf("archived tracker should be hidden, got %+v", list)
	}
}
