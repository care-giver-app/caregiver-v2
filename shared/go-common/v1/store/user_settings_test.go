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

func activeUser(id, email string) domain.User {
	return domain.User{
		UserID: id, Email: email, Name: "Name " + id, EmailNotifications: true,
		Status: domain.UserActive, CreatedAt: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
	}
}

func TestUserStore_Update(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	if _, err := s.Users.CreateIfAbsent(ctx, activeUser("u1", "u1@x.com")); err != nil {
		t.Fatal(err)
	}

	name, off := "Sam Lee", false
	u, err := s.Users.Update(ctx, "u1", store.UserChange{Name: &name})
	if err != nil || u.Name != "Sam Lee" || !u.EmailNotifications || u.Email != "u1@x.com" {
		t.Fatalf("name only: %+v %v", u, err)
	}
	u, err = s.Users.Update(ctx, "u1", store.UserChange{EmailNotifications: &off})
	if err != nil || u.Name != "Sam Lee" || u.EmailNotifications {
		t.Fatalf("notifications only: %+v %v", u, err)
	}
	if u, err := s.Users.Update(ctx, "u1", store.UserChange{}); err != nil || u.Name != "Sam Lee" {
		t.Fatalf("empty change reads the row: %+v %v", u, err)
	}
	if _, err := s.Users.Update(ctx, "nobody", store.UserChange{Name: &name}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing user: %v", err)
	}
	if _, err := s.Users.Get(ctx, "nobody"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("update must not create a row: %v", err)
	}
}

func TestUserStore_SetEmail(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	if _, err := s.Users.CreateIfAbsent(ctx, activeUser("u1", "old@x.com")); err != nil {
		t.Fatal(err)
	}
	if err := s.Users.SetEmail(ctx, "u1", "new@x.com"); err != nil {
		t.Fatal(err)
	}
	if u, _ := s.Users.Get(ctx, "u1"); u.Email != "new@x.com" {
		t.Fatalf("email = %q", u.Email)
	}
	if err := s.Users.SetEmail(ctx, "u1", ""); err == nil {
		t.Fatal("an empty address must be refused")
	}
	if err := s.Users.SetEmail(ctx, "nobody", "n@x.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing user: %v", err)
	}
}

func TestUserStore_Close(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	if _, err := s.Users.CreateIfAbsent(ctx, activeUser("u1", "u1@x.com")); err != nil {
		t.Fatal(err)
	}
	at := time.Date(2026, 11, 20, 9, 0, 0, 0, time.UTC)
	if err := s.Users.Close(ctx, "u1", at); err != nil {
		t.Fatal(err)
	}
	u, err := s.Users.Get(ctx, "u1")
	if err != nil || u.Status != domain.UserClosed || u.Name != "" || u.Email != "" || u.ClosedAt == nil || !u.ClosedAt.Equal(at) {
		t.Fatalf("closed row = %+v %v", u, err)
	}
	if ids, err := s.Users.IDsByEmail(ctx, "u1@x.com"); err != nil || len(ids) != 0 {
		t.Fatalf("a closed row must leave the email-index: %v %v", ids, err)
	}

	// Again: a no-op that keeps the first closed_at.
	if err := s.Users.Close(ctx, "u1", at.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if u, _ := s.Users.Get(ctx, "u1"); !u.ClosedAt.Equal(at) {
		t.Fatalf("closed_at moved: %v", u.ClosedAt)
	}
	// A closed row takes no more changes.
	name := "Back"
	if _, err := s.Users.Update(ctx, "u1", store.UserChange{Name: &name}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("update closed: %v", err)
	}
	if err := s.Users.SetEmail(ctx, "u1", "u1@x.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("set email on closed: %v", err)
	}
	if err := s.Users.Close(ctx, "nobody", at); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("close missing: %v", err)
	}
}

func TestUserStore_IDsByEmail(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	for _, u := range []domain.User{activeUser("u1", "a@x.com"), activeUser("u2", "b@x.com")} {
		if _, err := s.Users.CreateIfAbsent(ctx, u); err != nil {
			t.Fatal(err)
		}
	}
	if ids, err := s.Users.IDsByEmail(ctx, "a@x.com"); err != nil || len(ids) != 1 || ids[0] != "u1" {
		t.Fatalf("ids = %v %v", ids, err)
	}
	if ids, err := s.Users.IDsByEmail(ctx, "c@x.com"); err != nil || len(ids) != 0 {
		t.Fatalf("ids = %v %v", ids, err)
	}
}

func TestStores_SoleAdminOf(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	s := l.Stores
	now := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	team := func(id, name string, status domain.TeamStatus, members map[string]domain.Role) {
		seed(t, l, l.Names.Teams, domain.Team{TeamID: id, Name: name, Status: status, CreatedBy: "a", CreatedAt: now})
		for uid, role := range members {
			seed(t, l, l.Names.Memberships, domain.NewMembership(uid, id, role, now))
		}
	}
	team("t-alone", "Zeta", domain.TeamActive, map[string]domain.Role{"a": domain.RoleAdmin})
	team("t-sole", "Alpha", domain.TeamActive, map[string]domain.Role{"a": domain.RoleAdmin, "c": domain.RoleCaregiver})
	team("t-two", "Beta", domain.TeamActive, map[string]domain.Role{"a": domain.RoleAdmin, "b": domain.RoleAdmin})
	team("t-cg", "Gamma", domain.TeamActive, map[string]domain.Role{"a": domain.RoleCaregiver, "b": domain.RoleAdmin})
	team("t-arch", "Archived", domain.TeamArchived, map[string]domain.Role{"a": domain.RoleAdmin})

	got, err := s.SoleAdminOf(ctx, "a")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].TeamID != "t-sole" || got[1].TeamID != "t-alone" {
		t.Fatalf("sole admin of = %+v", got)
	}
	if got, err := s.SoleAdminOf(ctx, "c"); err != nil || len(got) != 0 {
		t.Fatalf("a caregiver is nobody's only admin: %+v %v", got, err)
	}
}
