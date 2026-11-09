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

var now = time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)

func loggedEntry(id, tracker string, at time.Time, vals map[string]any) domain.Entry {
	return domain.Entry{
		EntryID: id, TrackerID: tracker, ReceiverID: "r1", TeamID: "t1", State: domain.EntryLogged,
		Values: vals, OccurredAt: &at, LoggedBy: "u1", LoggedAt: &at, CreatedBy: "u1", CreatedAt: at, TimelineAt: at,
	}
}

func scheduledEntry(id, tracker string, at time.Time) domain.Entry {
	return domain.Entry{
		EntryID: id, TrackerID: tracker, ReceiverID: "r1", TeamID: "t1", State: domain.EntryScheduled,
		ScheduleID: "s1", OccurrenceAt: &at, OccurrenceLocal: at.Format("2006-01-02T15:04"),
		Values: map[string]any{}, CreatedBy: "u1", CreatedAt: now.Add(-30 * 24 * time.Hour), TimelineAt: at, OpenAt: &at,
	}
}

func skippedEntry(id, tracker string, at time.Time) domain.Entry {
	e := scheduledEntry(id, tracker, at)
	e.State, e.OpenAt, e.SkippedBy, e.SkippedAt = domain.EntrySkipped, nil, "u1", &now
	return e
}

func TestEntry_ListByTrackerTimeline(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	for i := 0; i < 5; i++ {
		seed(t, l, l.Names.Entries, loggedEntry(fmt.Sprintf("e%d", i), "tr1", now.Add(-time.Duration(i+1)*time.Hour), map[string]any{"sys": 120.0}))
	}
	seed(t, l, l.Names.Entries, scheduledEntry("past-open", "tr1", now.Add(-30*time.Minute)))
	seed(t, l, l.Names.Entries, skippedEntry("skipped", "tr1", now.Add(-90*time.Minute)))
	seed(t, l, l.Names.Entries, scheduledEntry("future", "tr1", now.Add(time.Hour)))
	seed(t, l, l.Names.Entries, loggedEntry("other", "tr2", now.Add(-time.Hour), nil))

	// Page through everything up to now, newest first, two at a time.
	var ids []string
	cursor := ""
	for page := 0; ; page++ {
		if page > 10 {
			t.Fatal("cursor never ended")
		}
		got, next, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now, nil, 2, cursor)
		if err != nil {
			t.Fatalf("page %d: %v", page, err)
		}
		for _, e := range got {
			ids = append(ids, e.EntryID)
		}
		if next == "" {
			break
		}
		cursor = next
	}
	want := []string{"past-open", "e0", "skipped", "e1", "e2", "e3", "e4"}
	if fmt.Sprint(ids) != fmt.Sprint(want) {
		t.Fatalf("got %v, want %v", ids, want)
	}

	from := now.Add(-2 * time.Hour)
	got, next, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now.Add(-time.Hour), &from, 50, "")
	if err != nil || next != "" || len(got) != 3 || got[0].EntryID != "e0" || got[1].EntryID != "skipped" || got[2].EntryID != "e1" {
		t.Fatalf("bounded: %+v next=%q err=%v", got, next, err)
	}
	if got[0].OccurredAt == nil || got[0].Values["sys"] != 120.0 || got[1].DisplayState(now) != domain.EntrySkipped {
		t.Fatalf("round trip: %+v", got[:2])
	}

	for _, bad := range []string{"!!!", "e30", "eyJlbnRyeV9pZCI6ImUxIn0"} { // last is {"entry_id":"e1"}: wrong key set
		if _, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now, nil, 2, bad); !errors.Is(err, store.ErrInvalidCursor) {
			t.Fatalf("cursor %q: want ErrInvalidCursor, got %v", bad, err)
		}
	}
}

func TestEntry_RecentLoggedByTracker(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	for i := 0; i < 6; i++ {
		seed(t, l, l.Names.Entries, loggedEntry(fmt.Sprintf("e%d", i), "tr1", now.Add(-time.Duration(i+1)*time.Hour), nil))
		seed(t, l, l.Names.Entries, skippedEntry(fmt.Sprintf("s%d", i), "tr1", now.Add(-time.Duration(i+1)*time.Hour-time.Minute)))
	}
	seed(t, l, l.Names.Entries, scheduledEntry("future", "tr1", now.Add(time.Hour)))

	got, err := l.Stores.Entries.RecentLoggedByTracker(ctx, "tr1", 4)
	if err != nil || len(got) != 4 || got[0].EntryID != "e0" || got[3].EntryID != "e3" {
		t.Fatalf("got %+v err=%v", got, err)
	}
	all, err := l.Stores.Entries.RecentLoggedByTracker(ctx, "tr1", store.RecentLoggedLimit)
	if err != nil || len(all) != 6 {
		t.Fatalf("all: %d err=%v", len(all), err)
	}
	if last := domain.LastLoggedAt(all); last == nil || !last.Equal(now.Add(-time.Hour)) {
		t.Fatalf("last logged: %v", last)
	}
	if none, err := l.Stores.Entries.RecentLoggedByTracker(ctx, "none", 10); err != nil || len(none) != 0 {
		t.Fatalf("none: %+v err=%v", none, err)
	}
}

func TestEntry_OpenByReceiver(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Entries, scheduledEntry("o-49h", "tr1", now.Add(-49*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("o-2h", "tr1", now.Add(-2*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("o-1h", "tr1", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("o-tr2", "tr2", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("o-future", "tr1", now.Add(time.Hour)))
	seed(t, l, l.Names.Entries, skippedEntry("skipped", "tr1", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, loggedEntry("logged", "tr1", now.Add(-time.Hour), nil))

	got, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "tr1", now.Add(-domain.UnrecordedWindow), now)
	if err != nil || len(got) != 2 || got[0].EntryID != "o-2h" || got[1].EntryID != "o-1h" {
		t.Fatalf("tracker: %+v err=%v", got, err)
	}
	all, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "", now.Add(-domain.UnrecordedWindow), now.Add(2*time.Hour))
	if err != nil || len(all) != 4 {
		t.Fatalf("receiver-wide: %+v err=%v", all, err)
	}

	tr := domain.Tracker{Status: domain.TrackerActive}
	att := domain.EvaluateAttention(tr, now, nil, got)
	if len(att) != 2 || att[0].EntryID != "o-2h" {
		t.Fatalf("attention: %+v", att)
	}
}

func TestEntry_DeleteFutureOpenForTracker(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Entries, scheduledEntry("f1", "tr1", now.Add(time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("f2", "tr1", now.Add(48*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("unrecorded", "tr1", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("other", "tr2", now.Add(time.Hour)))
	seed(t, l, l.Names.Entries, loggedEntry("future-logged", "tr1", now.Add(2*time.Hour), nil))

	n, err := l.Stores.Entries.DeleteFutureOpenForTracker(ctx, "tr1", now)
	if err != nil || n != 2 {
		t.Fatalf("deleted %d err=%v", n, err)
	}
	left, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now.Add(72*time.Hour), nil, 50, "")
	if err != nil || len(left) != 2 || left[0].EntryID != "future-logged" || left[1].EntryID != "unrecorded" {
		t.Fatalf("left: %+v err=%v", left, err)
	}
	if other, _ := l.Stores.Entries.OpenByReceiver(ctx, "r1", "tr2", now, now.Add(2*time.Hour)); len(other) != 1 {
		t.Fatalf("other tracker touched: %+v", other)
	}
	if n, err := l.Stores.Entries.DeleteFutureOpenForTracker(ctx, "tr1", now); err != nil || n != 0 {
		t.Fatalf("second run: %d err=%v", n, err)
	}
}

func TestEntry_DeleteFutureOpenForSchedule(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Entries, scheduledEntry("f1", "tr1", now.Add(time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("f2", "tr1", now.Add(48*time.Hour)))
	seed(t, l, l.Names.Entries, scheduledEntry("unrecorded", "tr1", now.Add(-time.Hour)))
	seed(t, l, l.Names.Entries, skippedEntry("future-skipped", "tr1", now.Add(3*time.Hour)))
	early := scheduledEntry("future-logged", "tr1", now.Add(2*time.Hour))
	early.State, early.OpenAt, early.OccurredAt, early.LoggedBy, early.TimelineAt = domain.EntryLogged, nil, &now, "u1", now
	seed(t, l, l.Names.Entries, early)
	other := scheduledEntry("other-schedule", "tr1", now.Add(time.Hour))
	other.ScheduleID = "s2"
	seed(t, l, l.Names.Entries, other)

	n, err := l.Stores.Entries.DeleteFutureOpenForSchedule(ctx, "s1", now)
	if err != nil || n != 2 {
		t.Fatalf("deleted %d err=%v", n, err)
	}
	left, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now.Add(72*time.Hour), nil, 50, "")
	var ids []string
	for _, e := range left {
		ids = append(ids, e.EntryID)
	}
	if err != nil || fmt.Sprint(ids) != "[future-skipped other-schedule future-logged unrecorded]" {
		t.Fatalf("left: %v err=%v", ids, err)
	}
	if n, err := l.Stores.Entries.DeleteFutureOpenForSchedule(ctx, "s1", now); err != nil || n != 0 {
		t.Fatalf("second run: %d err=%v", n, err)
	}
}

func TestEntry_CreateIfAbsent(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	e := scheduledEntry("occ", "tr1", now.Add(time.Hour))
	if created, err := l.Stores.Entries.CreateIfAbsent(ctx, e); err != nil || !created {
		t.Fatalf("first: %v %v", created, err)
	}
	logged := e
	logged.State, logged.OpenAt = domain.EntryLogged, nil
	seed(t, l, l.Names.Entries, logged)
	if created, err := l.Stores.Entries.CreateIfAbsent(ctx, e); err != nil || created {
		t.Fatalf("second: %v %v", created, err)
	}
	got, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now.Add(2*time.Hour), nil, 10, "")
	if err != nil || len(got) != 1 || got[0].State != domain.EntryLogged {
		t.Fatalf("overwritten: %+v err=%v", got, err)
	}
}

// Entry rows exactly as scripts/migrate_to_v1.py writes them.
func TestEntry_readsMigratedRows(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Entries, map[string]any{
		"entry_id": "ev", "tracker_id": "tr1", "receiver_id": "r1", "team_id": "t1", "state": "logged",
		"values":      map[string]any{"sys": 150, "amount": []any{"o1"}, "note": "after lunch", "ok": true},
		"occurred_at": "2026-11-08T10:00:00Z", "logged_by": "u1", "logged_at": "2026-11-08T10:05:00.5Z",
		"created_by": "u1", "created_at": "2026-11-08T10:05:00.5Z", "timeline_at": "2026-11-08T10:00:00Z", "note": "fine",
	})
	seed(t, l, l.Names.Entries, map[string]any{
		"entry_id": "si", "tracker_id": "tr1", "receiver_id": "r1", "team_id": "t1", "state": "scheduled",
		"occurrence_local": "2026-11-08T05:00", "occurrence_at": "2026-11-08T11:00:00Z",
		"planned_values": map[string]any{"where": "Clinic"}, "values": map[string]any{"where": "Clinic"},
		"unrecorded_alert": false, "created_by": "u1", "created_at": "2026-10-01T00:00:00Z",
		"timeline_at": "2026-11-08T11:00:00Z", "open_at": "2026-11-08T11:00:00Z",
	})

	got, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now, nil, 10, "")
	if err != nil || len(got) != 2 {
		t.Fatalf("list: %+v err=%v", got, err)
	}
	si, ev := got[0], got[1]
	if si.EntryID != "si" || si.DisplayState(now) != domain.EntryUnrecorded || si.ScheduleID != "" ||
		si.PlannedValues["where"] != "Clinic" || si.OpenAt == nil || si.OccurrenceLocal != "2026-11-08T05:00" {
		t.Fatalf("scheduled item: %+v", si)
	}
	if ev.EntryID != "ev" || ev.Values["sys"] != 150.0 || ev.Values["ok"] != true || ev.Note != "fine" ||
		ev.LoggedAt == nil || ev.LoggedAt.Nanosecond() != 500000000 {
		t.Fatalf("event: %+v", ev)
	}
	if opts, ok := ev.Values["amount"].([]any); !ok || len(opts) != 1 || opts[0] != "o1" {
		t.Fatalf("choice value: %#v", ev.Values["amount"])
	}

	tr := domain.Tracker{Status: domain.TrackerActive, Fields: []domain.Field{
		{FieldID: "sys", Type: domain.FieldNumber, Status: domain.FieldActive, Range: &domain.Range{High: f64(140)}},
	}}
	recent, _ := l.Stores.Entries.RecentLoggedByTracker(ctx, "tr1", store.RecentLoggedLimit)
	open, _ := l.Stores.Entries.OpenByReceiver(ctx, "r1", "tr1", now.Add(-domain.UnrecordedWindow), now)
	att := domain.EvaluateAttention(tr, now, recent, open)
	if len(att) != 2 || att[0].Kind != domain.AttentionUnrecorded || att[1].Kind != domain.AttentionOutOfRange || att[1].Value != 150 {
		t.Fatalf("attention over migrated rows: %+v", att)
	}
}
