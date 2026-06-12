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

func seedEvent(t *testing.T, s *store.Stores, id string, at time.Time) {
	t.Helper()
	e := domain.Event{
		TrackerID: "tr1", EventID: id, CareGroupID: "g1", ReceiverID: "r1",
		Values: map[string]any{"weight": 170.0}, OccurredAt: at, LoggedBy: "u1", CreatedAt: at,
	}
	if err := s.Events.Put(context.Background(), e); err != nil {
		t.Fatalf("seed %s: %v", id, err)
	}
}

func TestEventStore_putGetUpdateDelete(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	seedEvent(t, s, "e1", time.Now().UTC())

	got, err := s.Events.Get(ctx, "tr1", "e1")
	if err != nil || got.Values["weight"] != 170.0 {
		t.Fatalf("get: %+v err %v", got, err)
	}

	got.Values["weight"] = 168.0
	if err := s.Events.Update(ctx, got); err != nil {
		t.Fatalf("update: %v", err)
	}
	reread, _ := s.Events.Get(ctx, "tr1", "e1")
	if reread.Values["weight"] != 168.0 {
		t.Fatalf("update not persisted: %+v", reread)
	}

	if err := s.Events.Delete(ctx, "tr1", "e1"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.Events.Get(ctx, "tr1", "e1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestEventStore_listNewestFirstAndPaginate(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	base := time.Date(2026, 6, 12, 9, 0, 0, 0, time.UTC)
	seedEvent(t, s, "e1", base)
	seedEvent(t, s, "e2", base.Add(time.Hour))
	seedEvent(t, s, "e3", base.Add(2*time.Hour))

	page1, cur, err := s.Events.ListByTracker(ctx, "tr1", 2, "", nil, nil)
	if err != nil || len(page1) != 2 {
		t.Fatalf("page1: %d err %v", len(page1), err)
	}
	if page1[0].EventID != "e3" || page1[1].EventID != "e2" {
		t.Fatalf("expected newest-first e3,e2, got %s,%s", page1[0].EventID, page1[1].EventID)
	}
	if cur == "" {
		t.Fatal("expected a cursor for the next page")
	}
	page2, cur2, err := s.Events.ListByTracker(ctx, "tr1", 2, cur, nil, nil)
	if err != nil || len(page2) != 1 || page2[0].EventID != "e1" {
		t.Fatalf("page2: %+v err %v", page2, err)
	}
	if cur2 != "" {
		t.Fatalf("expected empty cursor at end, got %q", cur2)
	}
}

func TestEventStore_listRange(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	base := time.Date(2026, 6, 12, 9, 0, 0, 0, time.UTC)
	seedEvent(t, s, "e1", base)
	seedEvent(t, s, "e2", base.Add(time.Hour))
	seedEvent(t, s, "e3", base.Add(2*time.Hour))

	from := base.Add(30 * time.Minute)
	to := base.Add(90 * time.Minute)
	got, _, err := s.Events.ListByTracker(ctx, "tr1", 10, "", &from, &to)
	if err != nil || len(got) != 1 || got[0].EventID != "e2" {
		t.Fatalf("range expected only e2, got %+v err %v", got, err)
	}
}
