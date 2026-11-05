package store_test

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestUserStore_CreateIfAbsent_isIdempotent(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)
	u := domain.User{
		UserID: "sub-1", Email: "a@b.com", Name: "A", EmailNotifications: true,
		Status: domain.UserActive, CreatedAt: now,
	}

	created, err := s.Users.CreateIfAbsent(ctx, u)
	if err != nil || !created {
		t.Fatalf("first create: created=%v err=%v", created, err)
	}

	created2, err := s.Users.CreateIfAbsent(ctx, domain.User{UserID: "sub-1", Email: "x@y.com", Name: "X", Status: domain.UserActive})
	if err != nil || created2 {
		t.Fatalf("second create should be a no-op: created=%v err=%v", created2, err)
	}

	got, err := s.Users.Get(ctx, "sub-1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Email != "a@b.com" || got.Name != "A" || !got.EmailNotifications || got.Status != domain.UserActive ||
		got.ClosedAt != nil || !got.CreatedAt.Equal(now) {
		t.Fatalf("first write should be preserved, got %+v", got)
	}

	if _, err := s.Users.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}

func TestUserStore_closedUserWithoutEmail(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	closed := time.Now().UTC().Truncate(time.Second)
	u := domain.User{UserID: "sub-2", Status: domain.UserClosed, ClosedAt: &closed, CreatedAt: closed}
	if _, err := s.Users.CreateIfAbsent(ctx, u); err != nil {
		t.Fatalf("a closed user with no email must be writable (email-index key omitted): %v", err)
	}
	got, err := s.Users.Get(ctx, "sub-2")
	if err != nil || got.ClosedAt == nil || !got.ClosedAt.Equal(closed) || got.Email != "" {
		t.Fatalf("got %+v err=%v", got, err)
	}
}

func TestUserStore_BatchGet(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	var ids []string
	for i := 0; i < 130; i++ {
		id := fmt.Sprintf("u%03d", i)
		ids = append(ids, id)
		if _, err := s.Users.CreateIfAbsent(ctx, domain.User{UserID: id, Email: id + "@x.com", Name: "N" + id, Status: domain.UserActive, CreatedAt: now}); err != nil {
			t.Fatalf("seed %s: %v", id, err)
		}
	}

	// More than 100 ids (forces chunking), a duplicate, and a missing id.
	got, err := s.Users.BatchGet(ctx, append(ids, "u000", "missing"))
	if err != nil {
		t.Fatalf("batchget: %v", err)
	}
	if len(got) != 130 || got["u129"].Name != "Nu129" {
		t.Fatalf("want 130 users, got %d", len(got))
	}
	if _, ok := got["missing"]; ok {
		t.Fatal("missing id should be absent")
	}

	empty, err := s.Users.BatchGet(ctx, nil)
	if err != nil || len(empty) != 0 {
		t.Fatalf("empty batchget: %+v err=%v", empty, err)
	}
}
