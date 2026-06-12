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

func TestReceiverStore_putGetListArchive(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()

	r1 := domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedBy: "u1", CreatedAt: now}
	r2 := domain.Receiver{ReceiverID: "r2", CareGroupID: "g1", Name: "Dad", CreatedBy: "u1", CreatedAt: now.Add(time.Second)}
	for _, r := range []domain.Receiver{r1, r2} {
		if err := s.Receivers.Put(ctx, r); err != nil {
			t.Fatalf("put %s: %v", r.ReceiverID, err)
		}
	}

	got, err := s.Receivers.Get(ctx, "r1")
	if err != nil || got.Name != "Mom" {
		t.Fatalf("get r1: %+v err %v", got, err)
	}

	if _, err := s.Receivers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	list, err := s.Receivers.ListByGroup(ctx, "g1")
	if err != nil || len(list) != 2 {
		t.Fatalf("list g1: %d err %v", len(list), err)
	}

	if err := s.Receivers.Archive(ctx, "r1"); err != nil {
		t.Fatalf("archive r1: %v", err)
	}
	list, _ = s.Receivers.ListByGroup(ctx, "g1")
	if len(list) != 1 || list[0].ReceiverID != "r2" {
		t.Fatalf("archived receiver should be hidden, got %+v", list)
	}
}
