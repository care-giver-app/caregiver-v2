package main

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func put(t *testing.T, l dynamotest.Local, table string, v any) {
	t.Helper()
	item, err := store.MarshalItem(v)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := l.Client.PutItem(context.Background(), &dynamodb.PutItemInput{TableName: aws.String(table), Item: item}); err != nil {
		t.Fatal(err)
	}
}

func utc(s string) time.Time {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		panic(err)
	}
	return t
}

func schedule(id, trackerID string, now time.Time) domain.Schedule {
	return domain.Schedule{
		ScheduleID: id, TrackerID: trackerID, ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: domain.FreqWeekly, Interval: 1, ByDay: []string{"MO", "WE", "FR"}}, Time: "08:00", StartsOn: "2026-11-08",
		CreatedBy: "admin", CreatedAt: now,
	}
}

func testLogger() (*slog.Logger, *bytes.Buffer) {
	var buf bytes.Buffer
	return logger.NewWithWriter(&buf, "generator", "test", slog.LevelInfo), &buf
}

func TestRun_generatesLiveSchedulesAndRerunsWriteNothing(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	now := utc("2026-11-08T18:00:00Z") // Sunday noon in Chicago

	put(t, l, l.Names.Receivers, domain.Receiver{ReceiverID: "r1", TeamID: "t1", TimeZone: "America/Chicago", Status: domain.ReceiverActive})
	put(t, l, l.Names.Trackers, domain.Tracker{TrackerID: "active", ReceiverID: "r1", TeamID: "t1", Status: domain.TrackerActive})
	put(t, l, l.Names.Trackers, domain.Tracker{TrackerID: "paused", ReceiverID: "r1", TeamID: "t1", Status: domain.TrackerPaused})
	put(t, l, l.Names.Schedules, schedule("s-active", "active", now))
	put(t, l, l.Names.Schedules, schedule("s-paused", "paused", now))
	removed := schedule("s-removed", "active", now)
	removed.RemovedAt = &now
	put(t, l, l.Names.Schedules, removed)

	log, buf := testLogger()
	sum, err := Run(ctx, l.Stores, log, now)
	if err != nil {
		t.Fatalf("first run: %v", err)
	}
	if sum != (Summary{Schedules: 2, Skipped: 1, Written: 6}) {
		t.Fatalf("first run: %+v", sum)
	}
	if got := strings.Count(buf.String(), `"msg":"schedule generated"`); got != 2 {
		t.Fatalf("per-schedule log lines: %d\n%s", got, buf.String())
	}
	if !strings.Contains(buf.String(), `"msg":"run complete"`) {
		t.Fatalf("no run summary logged:\n%s", buf.String())
	}
	horizon := now.Add(30 * 24 * time.Hour)
	if open, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "paused", now, horizon); err != nil || len(open) != 0 {
		t.Fatalf("paused tracker got entries: %d err=%v", len(open), err)
	}
	if got, _ := l.Stores.Schedules.Get(ctx, "s-active"); got.GeneratedThrough != "2026-11-20" {
		t.Fatalf("generated_through: %q", got.GeneratedThrough)
	}

	sum, err = Run(ctx, l.Stores, log, now)
	if err != nil {
		t.Fatalf("re-run: %v", err)
	}
	if sum != (Summary{Schedules: 2, Skipped: 1, Present: 6}) {
		t.Fatalf("re-run: %+v", sum)
	}
	all, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "active", horizon, nil, 50, "")
	if err != nil || len(all) != 6 {
		t.Fatalf("entries after re-run: %d err=%v", len(all), err)
	}
}

func TestRun_continuesPastAFailedScheduleAndReportsIt(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	now := utc("2026-11-08T18:00:00Z")

	put(t, l, l.Names.Receivers, domain.Receiver{ReceiverID: "r1", TeamID: "t1", TimeZone: "America/Chicago", Status: domain.ReceiverActive})
	put(t, l, l.Names.Trackers, domain.Tracker{TrackerID: "active", ReceiverID: "r1", TeamID: "t1", Status: domain.TrackerActive})
	put(t, l, l.Names.Schedules, schedule("s-active", "active", now))
	put(t, l, l.Names.Schedules, schedule("s-orphan", "missing", now))

	log, buf := testLogger()
	sum, err := Run(ctx, l.Stores, log, now)
	if err == nil {
		t.Fatal("want an error when a schedule fails")
	}
	if sum != (Summary{Schedules: 2, Failed: 1, Written: 6}) {
		t.Fatalf("summary: %+v", sum)
	}
	if !strings.Contains(buf.String(), `"msg":"schedule failed"`) || !strings.Contains(buf.String(), `"schedule_id":"s-orphan"`) {
		t.Fatalf("failure not logged:\n%s", buf.String())
	}
}
