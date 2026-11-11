package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func note(id, receiver string, at time.Time) domain.JournalNote {
	return domain.JournalNote{
		NoteID: id, ReceiverID: receiver, TeamID: "t1", At: at, Body: "slept well",
		Author: "u1", CreatedAt: at,
	}
}

func TestJournalNote_CreateGetPutDelete(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	notes := l.Stores.JournalNotes

	n := note("n1", "r1", now.Add(-time.Hour))
	if err := notes.Create(ctx, n); err != nil {
		t.Fatalf("create: %v", err)
	}
	var ccf *types.ConditionalCheckFailedException
	if err := notes.Create(ctx, n); !errors.As(err, &ccf) {
		t.Fatalf("duplicate create: err=%v", err)
	}
	got, err := notes.Get(ctx, "n1")
	if err != nil || got.Body != "slept well" || !got.At.Equal(n.At) || got.Author != "u1" || got.UpdatedAt != nil || got.UpdatedBy != "" {
		t.Fatalf("get: %+v err=%v", got, err)
	}

	newAt := now.Add(-26 * time.Hour)
	edited, err := notes.Put(ctx, "n1", newAt, "slept badly", "u2", now)
	if err != nil {
		t.Fatalf("put: %v", err)
	}
	if edited.Body != "slept badly" || !edited.At.Equal(newAt) || edited.Author != "u1" || !edited.CreatedAt.Equal(n.CreatedAt) ||
		edited.UpdatedBy != "u2" || edited.UpdatedAt == nil || !edited.UpdatedAt.Equal(now) || edited.TeamID != "t1" {
		t.Fatalf("edited: %+v", edited)
	}
	if again, err := notes.Get(ctx, "n1"); err != nil || again.Body != "slept badly" {
		t.Fatalf("get after put: %+v err=%v", again, err)
	}
	if _, err := notes.Put(ctx, "nope", now, "x", "u2", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("put missing: err=%v", err)
	}

	if err := notes.Delete(ctx, "n1"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := notes.Get(ctx, "n1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("get after delete: err=%v", err)
	}
	if err := notes.Delete(ctx, "n1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("delete again: err=%v", err)
	}
}

func TestJournalNote_ListByReceiverBetween(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	notes := l.Stores.JournalNotes
	day := time.Date(2026, 11, 8, 5, 0, 0, 0, time.UTC)
	next := day.Add(24 * time.Hour)
	for _, n := range []domain.JournalNote{
		note("before", "r1", day.Add(-time.Nanosecond)),
		note("evening", "r1", day.Add(15*time.Hour)),
		note("start", "r1", day),
		note("end", "r1", next),
		note("other", "r2", day.Add(time.Hour)),
	} {
		if err := notes.Create(ctx, n); err != nil {
			t.Fatalf("create %s: %v", n.NoteID, err)
		}
	}
	got, err := notes.ListByReceiverBetween(ctx, "r1", day, next)
	if err != nil || len(got) != 2 || got[0].NoteID != "start" || got[1].NoteID != "evening" {
		t.Fatalf("got %+v err=%v", got, err)
	}
}
