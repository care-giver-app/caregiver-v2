package store_test

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func plannedEntry(id string, at time.Time) domain.Entry {
	e := scheduledEntry(id, "tr1", at)
	e.PlannedValues = map[string]any{"dose": 5.0}
	e.Values = map[string]any{"dose": 5.0}
	e.UnrecordedAlert = true
	return e
}

func care(at time.Time, vals map[string]any, note string) domain.EntryCare {
	return domain.EntryCare{OccurredAt: at, Values: vals, Note: note}
}

func TestEntry_LogConcurrentExactlyOneWins(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Entries, plannedEntry("e1", now.Add(-time.Hour)))

	const n = 8
	errs := make([]error, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			by := fmt.Sprintf("u%d", i)
			if i%2 == 0 {
				_, errs[i] = l.Stores.Entries.Log(ctx, "e1", care(now.Add(-30*time.Minute), map[string]any{"dose": 5.0}, by), by, now)
			} else {
				_, errs[i] = l.Stores.Entries.Skip(ctx, "e1", by, by, now)
			}
		}(i)
	}
	wg.Wait()
	won := 0
	for i, err := range errs {
		switch {
		case err == nil:
			won++
		case errors.Is(err, store.ErrEntryNotInState):
		default:
			t.Fatalf("writer %d: %v", i, err)
		}
	}
	if won != 1 {
		t.Fatalf("winners = %d, want exactly 1 (%v)", won, errs)
	}
	got, err := l.Stores.Entries.Get(ctx, "e1")
	if err != nil {
		t.Fatal(err)
	}
	if got.OpenAt != nil || (got.State != domain.EntryLogged && got.State != domain.EntrySkipped) {
		t.Fatalf("after race: %+v", got)
	}
}

func TestEntry_LogAndSkip(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	occ := now.Add(-time.Hour)
	seed(t, l, l.Names.Entries, plannedEntry("e1", occ))
	seed(t, l, l.Names.Entries, plannedEntry("e2", now.Add(2*time.Hour)))
	ran := now.Add(-20 * time.Minute)

	e, err := l.Stores.Entries.Log(ctx, "e1", care(ran, map[string]any{"dose": 10.0}, "with food"), "u2", now)
	if err != nil {
		t.Fatal(err)
	}
	if e.State != domain.EntryLogged || e.LoggedBy != "u2" || !e.LoggedAt.Equal(now) || !e.OccurredAt.Equal(ran) ||
		!e.TimelineAt.Equal(ran) || e.OpenAt != nil || e.Note != "with food" || e.Values["dose"] != 10.0 ||
		e.PlannedValues["dose"] != 5.0 || !e.OccurrenceAt.Equal(occ) || e.UpdatedBy != "" {
		t.Fatalf("logged: %+v", e)
	}
	// A future occurrence can be skipped; it keeps its place and values.
	s, err := l.Stores.Entries.Skip(ctx, "e2", "", "u3", now)
	if err != nil {
		t.Fatal(err)
	}
	if s.State != domain.EntrySkipped || s.SkippedBy != "u3" || !s.SkippedAt.Equal(now) || s.OpenAt != nil ||
		!s.TimelineAt.Equal(now.Add(2*time.Hour)) || s.Note != "" || s.Values["dose"] != 5.0 {
		t.Fatalf("skipped: %+v", s)
	}
	open, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "", now.Add(-48*time.Hour), now.Add(48*time.Hour))
	if err != nil || len(open) != 0 {
		t.Fatalf("open after settling: %v %+v", err, open)
	}
	// Settled entries cannot be settled again; a missing one is not found.
	if _, err := l.Stores.Entries.Log(ctx, "e2", care(ran, nil, ""), "u2", now); !errors.Is(err, store.ErrEntryNotInState) {
		t.Fatalf("log skipped: %v", err)
	}
	if _, err := l.Stores.Entries.Skip(ctx, "e1", "", "u2", now); !errors.Is(err, store.ErrEntryNotInState) {
		t.Fatalf("skip logged: %v", err)
	}
	if _, err := l.Stores.Entries.Log(ctx, "nope", care(ran, nil, ""), "u2", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("log missing: %v", err)
	}
	if _, err := l.Stores.Entries.Get(ctx, "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("log missing created a row: %v", err)
	}
}

func TestEntry_Change(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	at := now.Add(-3 * time.Hour)
	ad := loggedEntry("ad", "tr1", at, map[string]any{"sys": 120.0})
	ad.Note = "before"
	seed(t, l, l.Names.Entries, ad)
	seed(t, l, l.Names.Entries, skippedEntry("sk", "tr1", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("open", "tr1", now.Add(-time.Hour)))
	fixed := now.Add(-26 * time.Hour)

	e, err := l.Stores.Entries.Change(ctx, "ad", domain.EntryLogged, care(fixed, map[string]any{"sys": 121.0}, ""), "u2", now)
	if err != nil {
		t.Fatal(err)
	}
	if e.State != domain.EntryLogged || e.LoggedBy != "u1" || !e.LoggedAt.Equal(at) || e.UpdatedBy != "u2" ||
		!e.UpdatedAt.Equal(now) || !e.TimelineAt.Equal(fixed) || e.Note != "" || e.Values["sys"] != 121.0 {
		t.Fatalf("edited: %+v", e)
	}
	// Editing a skipped entry logs it, by whoever edited it.
	e, err = l.Stores.Entries.Change(ctx, "sk", domain.EntrySkipped, care(now.Add(-50*time.Minute), map[string]any{}, "given late"), "u3", now)
	if err != nil {
		t.Fatal(err)
	}
	if e.State != domain.EntryLogged || e.LoggedBy != "u3" || !e.LoggedAt.Equal(now) || e.SkippedBy != "" ||
		e.SkippedAt != nil || e.UpdatedBy != "u3" || e.OpenAt != nil || e.Note != "given late" {
		t.Fatalf("skipped then edited: %+v", e)
	}
	// A stale read: it is logged now, not skipped.
	if _, err := l.Stores.Entries.Change(ctx, "sk", domain.EntrySkipped, care(now, nil, ""), "u3", now); !errors.Is(err, store.ErrEntryNotInState) {
		t.Fatalf("stale edit: %v", err)
	}
	for _, from := range []domain.EntryState{domain.EntryScheduled, domain.EntryLogged} {
		if _, err := l.Stores.Entries.Change(ctx, "open", from, care(now, nil, ""), "u3", now); !errors.Is(err, store.ErrEntryNotInState) {
			t.Fatalf("edit scheduled as %s: %v", from, err)
		}
	}
}

func TestEntry_ReopenAndDeleteAdHoc(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	occ := now.Add(-time.Hour)
	seed(t, l, l.Names.Entries, plannedEntry("p", occ))
	seed(t, l, l.Names.Entries, plannedEntry("p2", now.Add(time.Hour)))
	seed(t, l, l.Names.Entries, loggedEntry("ad", "tr1", now.Add(-2*time.Hour), nil))

	logged, err := l.Stores.Entries.Log(ctx, "p", care(now.Add(-10*time.Minute), map[string]any{"dose": 20.0}, "n"), "u2", now)
	if err != nil {
		t.Fatal(err)
	}
	skipped, err := l.Stores.Entries.Skip(ctx, "p2", "not needed", "u2", now)
	if err != nil {
		t.Fatal(err)
	}
	later := now.Add(time.Minute)
	for _, e := range []domain.Entry{logged, skipped} {
		r, err := l.Stores.Entries.Reopen(ctx, e, "u4", later)
		if err != nil {
			t.Fatalf("reopen %s: %v", e.EntryID, err)
		}
		if r.State != domain.EntryScheduled || !reflect.DeepEqual(r.Values, map[string]any{"dose": 5.0}) ||
			r.OpenAt == nil || !r.OpenAt.Equal(*e.OccurrenceAt) || !r.TimelineAt.Equal(*e.OccurrenceAt) ||
			r.Note != "" || r.OccurredAt != nil || r.LoggedBy != "" || r.LoggedAt != nil || r.SkippedBy != "" ||
			r.SkippedAt != nil || r.UpdatedBy != "u4" || !r.UpdatedAt.Equal(later) || !r.UnrecordedAlert {
			t.Fatalf("reopened %s: %+v", e.EntryID, r)
		}
		// A second delete from the same read finds it waiting already.
		if _, err := l.Stores.Entries.Reopen(ctx, e, "u4", later); !errors.Is(err, store.ErrEntryNotInState) {
			t.Fatalf("reopen twice %s: %v", e.EntryID, err)
		}
	}
	open, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "", now.Add(-48*time.Hour), now.Add(48*time.Hour))
	if err != nil || len(open) != 2 || open[0].EntryID != "p" || open[1].EntryID != "p2" {
		t.Fatalf("open after reopen: %v %+v", err, open)
	}

	// An ad hoc entry cannot be reopened, and a planned one cannot be removed.
	ad, _ := l.Stores.Entries.Get(ctx, "ad")
	if _, err := l.Stores.Entries.Reopen(ctx, ad, "u4", later); !errors.Is(err, store.ErrEntryNotInState) {
		t.Fatalf("reopen ad hoc: %v", err)
	}
	if err := l.Stores.Entries.DeleteAdHoc(ctx, "p", domain.EntryScheduled); !errors.Is(err, store.ErrEntryNotInState) {
		t.Fatalf("delete planned: %v", err)
	}
	if err := l.Stores.Entries.DeleteAdHoc(ctx, "ad", domain.EntryLogged); err != nil {
		t.Fatal(err)
	}
	if _, err := l.Stores.Entries.Get(ctx, "ad"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("ad hoc after delete: %v", err)
	}
	if err := l.Stores.Entries.DeleteAdHoc(ctx, "ad", domain.EntryLogged); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("delete twice: %v", err)
	}
}
