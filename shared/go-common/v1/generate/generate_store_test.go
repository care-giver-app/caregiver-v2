package generate_test

import (
	"context"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
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

func TestGenerate_writesThroughTheStores(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	now := utc("2026-11-08T18:00:00Z") // Sunday noon in Chicago
	rc := domain.Receiver{ReceiverID: "r1", TeamID: "t1", TimeZone: "America/Chicago", Status: domain.ReceiverActive}
	tr := domain.Tracker{TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1", Status: domain.TrackerActive}
	sc := domain.Schedule{
		ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO", "WE", "FR"}}, Time: "08:00", StartsOn: "2026-11-08",
		PlannedValues: map[string]any{"dose": 5.0}, UnrecordedAlert: true, CreatedBy: "admin", CreatedAt: now,
	}
	put(t, l, l.Names.Schedules, sc)

	res, err := generate.Generate(ctx, l.Stores, sc, tr, rc, now, now)
	if err != nil || res.Written != 6 || res.Present != 0 || res.Through != "2026-11-20" {
		t.Fatalf("first run: %+v err=%v", res, err)
	}
	if got, _ := l.Stores.Schedules.Get(ctx, "s1"); got.GeneratedThrough != "2026-11-20" {
		t.Fatalf("generated_through: %q", got.GeneratedThrough)
	}
	open, err := l.Stores.Entries.OpenByReceiver(ctx, "r1", "tr1", now, now.Add(30*24*time.Hour))
	if err != nil || len(open) != 6 {
		t.Fatalf("open: %d err=%v", len(open), err)
	}
	first := open[0]
	if first.EntryID != generate.EntryID("s1", "2026-11-09T08:00") || first.OccurrenceLocal != "2026-11-09T08:00" ||
		!first.OccurrenceAt.Equal(utc("2026-11-09T14:00:00Z")) || first.Values["dose"] != 5.0 || !first.UnrecordedAlert {
		t.Fatalf("first: %+v", first)
	}

	// Someone logs Monday's early; a re-run (or a concurrent one) neither duplicates nor overwrites it.
	logged := first
	logged.State, logged.OpenAt, logged.LoggedBy = domain.EntryLogged, nil, "cg"
	put(t, l, l.Names.Entries, logged)
	res, err = generate.Generate(ctx, l.Stores, sc, tr, rc, now, now)
	if err != nil || res.Written != 0 || res.Present != 6 {
		t.Fatalf("re-run: %+v err=%v", res, err)
	}
	all, _, _ := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now.Add(30*24*time.Hour), nil, 50, "")
	if len(all) != 6 {
		t.Fatalf("entries after re-run: %d", len(all))
	}
	for _, e := range all {
		if e.EntryID == first.EntryID && e.State != domain.EntryLogged {
			t.Fatalf("logged occurrence overwritten: %+v", e)
		}
	}

	// A day later the window has moved on by one occurrence.
	later := now.Add(48 * time.Hour)
	if res, err = generate.Generate(ctx, l.Stores, sc, tr, rc, later, later); err != nil || res.Written != 1 || res.Through != "2026-11-23" {
		t.Fatalf("later: %+v err=%v", res, err)
	}
}

func TestGenerate_skips(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	now := utc("2026-11-08T18:00:00Z")
	removed := now
	rc := domain.Receiver{ReceiverID: "r1", TimeZone: "America/Chicago", Status: domain.ReceiverActive}
	tr := domain.Tracker{TrackerID: "tr1", Status: domain.TrackerActive}
	sc := domain.Schedule{ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, Time: "08:00", StartsOn: "2026-11-08", CreatedAt: now}
	put(t, l, l.Names.Schedules, sc)

	paused, archived, gone := tr, rc, sc
	paused.Status, archived.Status, gone.RemovedAt = domain.TrackerPaused, domain.ReceiverArchived, &removed
	for name, run := range map[string]func() (generate.Result, error){
		"paused tracker":    func() (generate.Result, error) { return generate.Generate(ctx, l.Stores, sc, paused, rc, now, now) },
		"archived receiver": func() (generate.Result, error) { return generate.Generate(ctx, l.Stores, sc, tr, archived, now, now) },
		"removed schedule":  func() (generate.Result, error) { return generate.Generate(ctx, l.Stores, gone, tr, rc, now, now) },
	} {
		if res, err := run(); err != nil || !res.Skipped || res.Written != 0 {
			t.Fatalf("%s: %+v err=%v", name, res, err)
		}
	}

	// Removed while generating: what it wrote is taken back.
	if err := l.Stores.Schedules.MarkRemoved(ctx, "s1", now); err != nil {
		t.Fatal(err)
	}
	if res, err := generate.Generate(ctx, l.Stores, sc, tr, rc, now, now); err != nil || !res.Skipped {
		t.Fatalf("raced removal: %+v err=%v", res, err)
	}
	if open, _ := l.Stores.Entries.OpenByReceiver(ctx, "r1", "", now, now.Add(30*24*time.Hour)); len(open) != 0 {
		t.Fatalf("a removed schedule left %d occurrences", len(open))
	}
}
