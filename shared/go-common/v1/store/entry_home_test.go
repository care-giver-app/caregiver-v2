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

func ids(es []domain.Entry) []string {
	out := make([]string, len(es))
	for i, e := range es {
		out[i] = e.EntryID
	}
	return out
}

func sameIDs(got []domain.Entry, want ...string) bool {
	g := ids(got)
	if len(g) != len(want) {
		return false
	}
	for i := range g {
		if g[i] != want[i] {
			return false
		}
	}
	return true
}

func TestEntry_Get(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Entries, loggedEntry("e1", "tr1", now, map[string]any{"sys": 120.0}))

	got, err := l.Stores.Entries.Get(ctx, "e1")
	if err != nil || got.EntryID != "e1" || got.State != domain.EntryLogged || got.Values["sys"] != 120.0 {
		t.Fatalf("got %+v err=%v", got, err)
	}
	if _, err := l.Stores.Entries.Get(ctx, "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing: err=%v", err)
	}
}

func TestEntry_ListByReceiverBetween(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	day := time.Date(2026, 11, 8, 5, 0, 0, 0, time.UTC) // a local midnight in UTC-5
	next := day.Add(24 * time.Hour)
	seed(t, l, l.Names.Entries, loggedEntry("before", "tr1", day.Add(-time.Nanosecond), nil))
	seed(t, l, l.Names.Entries, loggedEntry("at-start", "tr1", day, nil))
	seed(t, l, l.Names.Entries, skippedEntry("skipped", "tr2", day.Add(2*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("unrecorded", "tr1", day.Add(3*time.Hour)))
	seed(t, l, l.Names.Entries, loggedEntry("paused-tracker", "tr-paused", day.Add(4*time.Hour), nil))
	seed(t, l, l.Names.Entries, scheduledEntry("later-today", "tr1", next.Add(-time.Minute)))
	seed(t, l, l.Names.Entries, loggedEntry("at-end", "tr1", next, nil))
	other := loggedEntry("other-receiver", "tr9", day.Add(time.Hour), nil)
	other.ReceiverID = "r2"
	seed(t, l, l.Names.Entries, other)

	got, err := l.Stores.Entries.ListByReceiverBetween(ctx, "r1", day, next)
	if err != nil || !sameIDs(got, "at-start", "skipped", "unrecorded", "paused-tracker", "later-today") {
		t.Fatalf("got %v err=%v", ids(got), err)
	}
	empty, err := l.Stores.Entries.ListByReceiverBetween(ctx, "r1", next, next)
	if err != nil || len(empty) != 0 {
		t.Fatalf("empty range: %v err=%v", ids(empty), err)
	}
}

func TestEntry_NextOpenByTracker(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	// Meds twice a day for the next while; an appointment next Thursday.
	for i := 0; i < 10; i++ {
		at := now.Add(time.Duration(i*12+2) * time.Hour)
		seed(t, l, l.Names.Entries, scheduledEntry("meds-"+string(rune('a'+i)), "meds", at))
	}
	seed(t, l, l.Names.Entries, scheduledEntry("meds-past", "meds", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("meds-now", "meds", now))
	seed(t, l, l.Names.Entries, scheduledEntry("appt", "appt", now.Add(4*24*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("bp-next", "bp", now.Add(30*time.Minute)))
	seed(t, l, l.Names.Entries, skippedEntry("bp-skipped", "bp", now.Add(10*time.Minute)))
	seed(t, l, l.Names.Entries, scheduledEntry("paused-next", "paused", now.Add(5*time.Minute)))

	got, err := l.Stores.Entries.NextOpenByTracker(ctx, "r1", []string{"meds", "appt", "bp", "nothing-planned"}, now)
	if err != nil || !sameIDs(got, "bp-next", "meds-a", "appt") {
		t.Fatalf("got %v err=%v", ids(got), err)
	}
	none, err := l.Stores.Entries.NextOpenByTracker(ctx, "r1", nil, now)
	if err != nil || len(none) != 0 {
		t.Fatalf("no trackers: %v err=%v", ids(none), err)
	}
}

func TestEntry_waitingList(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	endOfToday := time.Date(2026, 11, 9, 5, 0, 0, 0, time.UTC) // local midnight in UTC-5
	seed(t, l, l.Names.Entries, scheduledEntry("49h", "tr1", now.Add(-49*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("47h", "tr1", now.Add(-47*time.Hour)))
	seed(t, l, l.Names.Entries, skippedEntry("skipped", "tr1", now.Add(-2*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("tonight", "tr1", endOfToday.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("tomorrow", "tr1", endOfToday))

	got, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "", now.Add(-domain.UnrecordedWindow), endOfToday.Add(-time.Nanosecond))
	if err != nil || !sameIDs(got, "47h", "tonight") {
		t.Fatalf("got %v err=%v", ids(got), err)
	}
}
