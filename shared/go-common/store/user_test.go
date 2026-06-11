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

func TestUserStore_CreateIfAbsent_andGet(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	u := domain.User{UserID: "sub-1", Email: "a@b.com", Name: "A", CreatedAt: time.Now().UTC().Truncate(time.Second)}

	created, err := s.Users.CreateIfAbsent(ctx, u)
	if err != nil || !created {
		t.Fatalf("first create: created=%v err=%v", created, err)
	}

	created2, err := s.Users.CreateIfAbsent(ctx, domain.User{UserID: "sub-1", Email: "x@y.com", Name: "X"})
	if err != nil || created2 {
		t.Fatalf("second create: created=%v err=%v", created2, err)
	}

	got, err := s.Users.Get(ctx, "sub-1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Email != "a@b.com" {
		t.Fatalf("expected original email, got %q", got.Email)
	}

	if _, err := s.Users.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
