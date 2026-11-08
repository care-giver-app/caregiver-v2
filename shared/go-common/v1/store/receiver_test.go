package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestReceiver_GetAndListActiveByTeam(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	base := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
	archivedAt := base.Add(time.Hour)

	for _, r := range []domain.Receiver{
		{ReceiverID: "r-new", TeamID: "t1", Name: "Pesto", Status: domain.ReceiverActive, CreatedAt: base.Add(48 * time.Hour)},
		{ReceiverID: "r-old", TeamID: "t1", Name: "Michele", Status: domain.ReceiverActive, CreatedAt: base},
		{ReceiverID: "r-gone", TeamID: "t1", Name: "Gone", Status: domain.ReceiverArchived, ArchivedBy: "u1", ArchivedAt: &archivedAt, CreatedAt: base.Add(time.Hour)},
		{ReceiverID: "r-other", TeamID: "t2", Name: "Other", Status: domain.ReceiverActive, CreatedAt: base},
	} {
		r.TimeZone, r.CreatedBy = "America/Chicago", "u1"
		seed(t, l, l.Names.Receivers, r)
	}

	got, err := l.Stores.Receivers.Get(ctx, "r-gone")
	if err != nil || got.Status != domain.ReceiverArchived || got.ArchivedAt == nil || got.TimeZone != "America/Chicago" {
		t.Fatalf("get: %+v err=%v", got, err)
	}
	if _, err := l.Stores.Receivers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	list, err := l.Stores.Receivers.ListActiveByTeam(ctx, "t1")
	if err != nil || len(list) != 2 || list[0].ReceiverID != "r-old" || list[1].ReceiverID != "r-new" {
		t.Fatalf("list: %+v err=%v", list, err)
	}
	if empty, err := l.Stores.Receivers.ListActiveByTeam(ctx, "none"); err != nil || len(empty) != 0 {
		t.Fatalf("empty: %+v err=%v", empty, err)
	}
}

// A receiver row exactly as scripts/migrate_to_v1.py writes it.
func TestReceiver_readsMigratedRow(t *testing.T) {
	l := dynamotest.StartLocal(t)
	seed(t, l, l.Names.Receivers, map[string]any{
		"receiver_id": "r1", "team_id": "t1", "name": "Michele", "time_zone": "America/Chicago",
		"status": "active", "created_by": "u1", "created_at": "2026-06-12T14:30:00.123456Z",
	})
	got, err := l.Stores.Receivers.Get(context.Background(), "r1")
	if err != nil || got.Name != "Michele" || got.Status != domain.ReceiverActive ||
		!got.CreatedAt.Equal(time.Date(2026, 6, 12, 14, 30, 0, 123456000, time.UTC)) {
		t.Fatalf("got %+v err=%v", got, err)
	}
}
