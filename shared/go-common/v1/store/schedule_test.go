package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
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
