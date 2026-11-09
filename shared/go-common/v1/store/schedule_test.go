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

func TestSchedule_ListAndCountLive(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	base := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	removed := base.Add(time.Hour)

	for _, sc := range []domain.Schedule{
		{ScheduleID: "evening", TrackerID: "tr1", CreatedAt: base.Add(2 * time.Hour), Time: "20:00"},
		{ScheduleID: "morning", TrackerID: "tr1", CreatedAt: base, Time: "08:00", Label: "Morning dose",
			PlannedValues: map[string]any{"dose": 5.0, "with": []any{"o1"}}, GraceMinutes: ptr(30), UnrecordedAlert: true},
		{ScheduleID: "gone", TrackerID: "tr1", CreatedAt: base.Add(time.Hour), Time: "12:00", RemovedAt: &removed},
		{ScheduleID: "other", TrackerID: "tr2", CreatedAt: base, Time: "09:00"},
	} {
		sc.ReceiverID, sc.TeamID, sc.CreatedBy, sc.StartsOn = "r1", "t1", "u1", "2026-11-01"
		sc.Rule = domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO", "TH"}}
		seed(t, l, l.Names.Schedules, sc)
	}

	live, err := l.Stores.Schedules.ListLiveByTracker(ctx, "tr1")
	if err != nil || len(live) != 2 || live[0].ScheduleID != "morning" || live[1].ScheduleID != "evening" {
		t.Fatalf("live: %+v err=%v", live, err)
	}
	m := live[0]
	if m.Label != "Morning dose" || m.Rule.Interval != 1 || len(m.Rule.ByDay) != 2 || m.PlannedValues["dose"] != 5.0 ||
		m.GraceMinutes == nil || *m.GraceMinutes != 30 || !m.UnrecordedAlert || m.StartsOn != "2026-11-01" || m.RemovedAt != nil {
		t.Fatalf("morning: %+v", m)
	}
	if n, err := l.Stores.Schedules.CountLiveByTracker(ctx, "tr1"); err != nil || n != 2 {
		t.Fatalf("count: %d err=%v", n, err)
	}
	if n, err := l.Stores.Schedules.CountLiveByTracker(ctx, "none"); err != nil || n != 0 {
		t.Fatalf("count none: %d err=%v", n, err)
	}
}

func ptr[T any](v T) *T { return &v }

func liveSchedule(id, tracker string) domain.Schedule {
	return domain.Schedule{
		ScheduleID: id, TrackerID: tracker, ReceiverID: "r1", TeamID: "t1", Label: "Morning dose",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, Time: "08:00", StartsOn: "2026-11-01",
		EndsOn: "2026-12-01", PlannedValues: map[string]any{"dose": 5.0}, UnrecordedAlert: true, GraceMinutes: ptr(15),
		GeneratedThrough: "2026-11-15", CreatedBy: "u1", CreatedAt: now,
	}
}

func TestSchedule_UpdateWritesOnlyTheSave(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Schedules, liveSchedule("s1", "tr1"))

	got, err := l.Stores.Schedules.Update(ctx, domain.Schedule{
		ScheduleID: "s1", Rule: domain.Rule{Freq: "weekly", Interval: 2, ByDay: []string{"TU", "TH"}}, Time: "09:30",
		PlannedValues: map[string]any{}, UnrecordedAlert: false, UpdatedAt: now.Add(time.Hour),
		// Not the Save's to change:
		TrackerID: "other", StartsOn: "2030-01-01", GeneratedThrough: "x", CreatedBy: "x",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.Label != "" || got.EndsOn != "" || got.Time != "09:30" || got.Rule.Interval != 2 || len(got.Rule.ByDay) != 2 ||
		len(got.PlannedValues) != 0 || got.UnrecordedAlert || got.TrackerID != "tr1" || got.StartsOn != "2026-11-01" ||
		got.GeneratedThrough != "2026-11-15" || got.CreatedBy != "u1" || got.GraceMinutes == nil || !got.UpdatedAt.Equal(now.Add(time.Hour)) {
		t.Fatalf("updated: %+v", got)
	}
	got, err = l.Stores.Schedules.Update(ctx, domain.Schedule{ScheduleID: "s1", Label: "Evening", EndsOn: "2026-12-24",
		Rule: got.Rule, Time: "20:00", PlannedValues: map[string]any{"dose": 2.0}})
	if err != nil || got.Label != "Evening" || got.EndsOn != "2026-12-24" || got.PlannedValues["dose"] != 2.0 {
		t.Fatalf("relabelled: %+v err=%v", got, err)
	}

	if _, err := l.Stores.Schedules.Update(ctx, domain.Schedule{ScheduleID: "missing", PlannedValues: map[string]any{}}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing: %v", err)
	}
	if err := l.Stores.Schedules.MarkRemoved(ctx, "s1", now); err != nil {
		t.Fatal(err)
	}
	if _, err := l.Stores.Schedules.Update(ctx, domain.Schedule{ScheduleID: "s1", PlannedValues: map[string]any{}}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("removed: %v", err)
	}
}

func TestSchedule_MarkRemovedAndBookmark(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	seed(t, l, l.Names.Schedules, liveSchedule("s1", "tr1"))
	seed(t, l, l.Names.Schedules, liveSchedule("s2", "tr2"))

	if err := l.Stores.Schedules.SetGeneratedThrough(ctx, "s1", "2026-11-22", time.Time{}); err != nil {
		t.Fatal(err)
	}
	// Changed since the generator's copy: the bookmark is refused.
	if err := l.Stores.Schedules.SetGeneratedThrough(ctx, "s1", "2026-11-29", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("bookmark on a changed schedule: %v", err)
	}
	if sc, err := l.Stores.Schedules.Get(ctx, "s1"); err != nil || sc.GeneratedThrough != "2026-11-22" {
		t.Fatalf("bookmark: %+v err=%v", sc, err)
	}
	if err := l.Stores.Schedules.MarkRemoved(ctx, "s1", now); err != nil {
		t.Fatal(err)
	}
	sc, err := l.Stores.Schedules.Get(ctx, "s1")
	if err != nil || sc.RemovedAt == nil || !sc.RemovedAt.Equal(now) {
		t.Fatalf("removed: %+v err=%v", sc, err)
	}
	if err := l.Stores.Schedules.MarkRemoved(ctx, "s1", now.Add(time.Hour)); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("removed twice: %v", err)
	}
	if err := l.Stores.Schedules.MarkRemoved(ctx, "missing", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing: %v", err)
	}
	if err := l.Stores.Schedules.SetGeneratedThrough(ctx, "s1", "2026-12-01", time.Time{}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("bookmark on removed: %v", err)
	}
	if _, err := l.Stores.Schedules.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("get missing: %v", err)
	}

	live, err := l.Stores.Schedules.ListLive(ctx)
	if err != nil || len(live) != 1 || live[0].ScheduleID != "s2" {
		t.Fatalf("live: %+v err=%v", live, err)
	}
}

func TestStores_AddSchedule(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	gap := 72
	seed(t, l, l.Names.Trackers, domain.Tracker{TrackerID: "plain", ReceiverID: "r1", TeamID: "t1", Name: "Meds", Status: domain.TrackerActive, CreatedAt: now})
	seed(t, l, l.Names.Trackers, domain.Tracker{TrackerID: "gapped", ReceiverID: "r1", TeamID: "t1", Name: "Shower", GapHours: &gap, Status: domain.TrackerActive, CreatedAt: now})

	if err := l.Stores.AddSchedule(ctx, liveSchedule("s1", "plain"), false); err != nil {
		t.Fatal(err)
	}
	if err := l.Stores.AddSchedule(ctx, liveSchedule("s1", "plain"), false); err == nil {
		t.Fatal("an id collision overwrote a schedule")
	}
	if err := l.Stores.AddSchedule(ctx, liveSchedule("s2", "gapped"), false); !errors.Is(err, store.ErrTrackerHasGap) {
		t.Fatalf("gapped: %v", err)
	}
	if _, err := l.Stores.Schedules.Get(ctx, "s2"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("a refused schedule was written: %v", err)
	}
	if err := l.Stores.AddSchedule(ctx, liveSchedule("s2", "gapped"), true); err != nil {
		t.Fatal(err)
	}
	if tr, err := l.Stores.Trackers.Get(ctx, "gapped"); err != nil || tr.GapHours != nil || tr.Name != "Shower" {
		t.Fatalf("gap not replaced: %+v err=%v", tr, err)
	}
	for _, replace := range []bool{false, true} {
		if err := l.Stores.AddSchedule(ctx, liveSchedule(fmt.Sprintf("s-missing-%v", replace), "missing"), replace); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("missing tracker (replace %v): %v", replace, err)
		}
	}
}
