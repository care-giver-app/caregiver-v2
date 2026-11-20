package generate_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func tuesdays(start, end string) domain.CoverageSchedule {
	created := utc("2026-11-08T18:00:00Z")
	return domain.CoverageSchedule{
		CoverageScheduleID: "cs1", ReceiverID: "r1", TeamID: "t1", UserID: "cg",
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"TU"}}, StartTime: start, EndTime: end,
		StartsOn: "2026-11-08", CreatedBy: "admin", CreatedAt: created, UpdatedAt: created,
	}
}

func TestExpandCoverage(t *testing.T) {
	loc := chicago(t)
	now := utc("2026-11-08T18:00:00Z") // Sunday noon in Chicago

	slots, err := generate.ExpandCoverage(tuesdays("08:00", "16:00"), loc, now, now)
	if err != nil || len(slots) != 2 {
		t.Fatalf("slots: %+v %v", slots, err)
	}
	if s := slots[0]; s.Date != "2026-11-10" || s.StartsLocal != "2026-11-10T08:00" || s.EndsLocal != "2026-11-10T16:00" ||
		!s.StartsAt.Equal(utc("2026-11-10T14:00:00Z")) || !s.EndsAt.Equal(utc("2026-11-10T22:00:00Z")) {
		t.Fatalf("first: %+v", s)
	}

	// Overnight: an end at or before the start is the next day.
	slots, _ = generate.ExpandCoverage(tuesdays("22:00", "06:00"), loc, now, now)
	if s := slots[0]; s.EndsLocal != "2026-11-11T06:00" || !s.EndsAt.Equal(utc("2026-11-11T12:00:00Z")) {
		t.Fatalf("overnight: %+v", s)
	}

	// A slot under way at from is included; one already over is not.
	tuesday10am := utc("2026-11-10T16:00:00Z")
	slots, _ = generate.ExpandCoverage(tuesdays("08:00", "16:00"), loc, tuesday10am, tuesday10am)
	if len(slots) < 1 || slots[0].Date != "2026-11-10" {
		t.Fatalf("under way: %+v", slots)
	}
	tuesday5pm := utc("2026-11-10T23:00:00Z")
	slots, _ = generate.ExpandCoverage(tuesdays("08:00", "16:00"), loc, tuesday5pm, tuesday5pm)
	if len(slots) < 1 || slots[0].Date != "2026-11-17" {
		t.Fatalf("over: %+v", slots)
	}
	// An overnight slot from Monday night is still under way on Tuesday morning.
	mon := tuesdays("22:00", "06:00")
	mon.Rule.ByDay = []string{"MO"}
	tuesday3am := utc("2026-11-10T09:00:00Z")
	slots, _ = generate.ExpandCoverage(mon, loc, tuesday3am, tuesday3am)
	if len(slots) < 1 || slots[0].Date != "2026-11-09" {
		t.Fatalf("overnight under way: %+v", slots)
	}

	// Every eight weeks: the next one beyond the horizon is still made.
	rare := tuesdays("08:00", "16:00")
	rare.Rule.Interval = 8
	rare.StartsOn = "2026-11-12"
	slots, _ = generate.ExpandCoverage(rare, loc, now, now)
	if len(slots) != 1 || slots[0].Date != "2027-01-05" {
		t.Fatalf("rare: %+v", slots)
	}

	// ends_on is inclusive.
	ending := tuesdays("08:00", "16:00")
	ending.EndsOn = "2026-11-10"
	if slots, _ = generate.ExpandCoverage(ending, loc, now, now); len(slots) != 1 {
		t.Fatalf("ending: %+v", slots)
	}
}

func TestExpandCoverage_daylightSaving(t *testing.T) {
	loc := chicago(t)
	// Saturday night 22:00 CDT to Sunday 06:00 CST, the night clocks fall back:
	// nine hours, keeping both wall-clock times.
	sat := tuesdays("22:00", "06:00")
	sat.Rule.ByDay, sat.StartsOn = []string{"SA"}, "2026-10-25"
	now := utc("2026-10-30T12:00:00Z")
	slots, err := generate.ExpandCoverage(sat, loc, now, now)
	if err != nil || len(slots) == 0 {
		t.Fatalf("%+v %v", slots, err)
	}
	if s := slots[0]; s.Date != "2026-10-31" || s.EndsAt.Sub(s.StartsAt) != 9*time.Hour {
		t.Fatalf("fall back: %+v", s)
	}
}

// leave deletes a membership row outright.
func leave(t *testing.T, l dynamotest.Local, userID, teamID string) {
	t.Helper()
	_, err := l.Client.DeleteItem(context.Background(), &dynamodb.DeleteItemInput{
		TableName: aws.String(l.Names.Memberships),
		Key: map[string]types.AttributeValue{
			"user_id": &types.AttributeValueMemberS{Value: userID}, "team_id": &types.AttributeValueMemberS{Value: teamID},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestAssignmentID_isDeterministicByDate(t *testing.T) {
	a := generate.AssignmentID("cs1", "2026-11-10")
	if a != generate.AssignmentID("cs1", "2026-11-10") || a == generate.AssignmentID("cs1", "2026-11-17") ||
		a == generate.AssignmentID("cs2", "2026-11-10") || a == generate.EntryID("cs1", "2026-11-10") {
		t.Fatal("ids")
	}
}

// coverageFixture is team t1 with admin and caregiver "cg", receiver r1 in
// Chicago, and rule cs1 (cg, Tuesdays 08:00–16:00) stored.
func coverageFixture(t *testing.T) (dynamotest.Local, domain.CoverageSchedule, domain.Receiver) {
	t.Helper()
	l := dynamotest.StartLocal(t)
	rc := domain.Receiver{ReceiverID: "r1", TeamID: "t1", TimeZone: "America/Chicago", Status: domain.ReceiverActive}
	cs := tuesdays("08:00", "16:00")
	put(t, l, l.Names.Receivers, rc)
	put(t, l, l.Names.Teams, activeTeam)
	put(t, l, l.Names.Memberships, domain.NewMembership("cg", "t1", domain.RoleCaregiver, cs.CreatedAt))
	put(t, l, l.Names.CoverageSchedules, cs)
	return l, cs, rc
}

func TestGenerateCoverage_writesThroughTheStores(t *testing.T) {
	l, cs, rc := coverageFixture(t)
	ctx := context.Background()
	now := cs.CreatedAt

	res, err := generate.GenerateCoverage(ctx, l.Stores, cs, rc, now, now)
	if err != nil || res.Written != 2 || res.Through != "2026-11-17" {
		t.Fatalf("first: %+v %v", res, err)
	}
	if got, _ := l.Stores.CoverageSchedules.Get(ctx, "cs1"); got.GeneratedThrough != "2026-11-17" {
		t.Fatalf("generated_through: %q", got.GeneratedThrough)
	}
	got, _ := l.Stores.Assignments.NotEndedByReceiver(ctx, "r1", now)
	if len(got) != 2 || got[0].AssignmentID != generate.AssignmentID("cs1", "2026-11-10") || got[0].UserID != "cg" ||
		got[0].OccurrenceLocal != "2026-11-10" || got[0].RuleID() != "cs1" || got[0].CreatedBy != "admin" {
		t.Fatalf("assignments: %+v", got)
	}

	// The first Tuesday is handed to the admin and the second removed; a
	// re-run makes neither again.
	first := got[0]
	first.UserID = "admin"
	if _, err := l.Stores.Assignments.Change(ctx, first, "admin", now); err != nil {
		t.Fatal(err)
	}
	if err := l.Stores.Assignments.Remove(ctx, got[1], "admin", now); err != nil {
		t.Fatal(err)
	}
	res, err = generate.GenerateCoverage(ctx, l.Stores, cs, rc, now, now)
	if err != nil || res.Written != 0 || res.Present != 2 {
		t.Fatalf("re-run: %+v %v", res, err)
	}
	got, _ = l.Stores.Assignments.NotEndedByReceiver(ctx, "r1", now)
	if len(got) != 1 || got[0].UserID != "admin" || got[0].RuleID() != "" {
		t.Fatalf("after re-run: %+v", got)
	}
}

func TestGenerateCoverage_skips(t *testing.T) {
	now := utc("2026-11-08T18:00:00Z")
	ctx := context.Background()
	for name, mutate := range map[string]func(l dynamotest.Local, cs *domain.CoverageSchedule, rc *domain.Receiver){
		"removed": func(_ dynamotest.Local, cs *domain.CoverageSchedule, _ *domain.Receiver) { cs.RemovedAt = &now },
		"archived": func(_ dynamotest.Local, _ *domain.CoverageSchedule, rc *domain.Receiver) {
			rc.Status = domain.ReceiverArchived
		},
		"ended": func(_ dynamotest.Local, cs *domain.CoverageSchedule, _ *domain.Receiver) { cs.EndsOn = "2026-11-07" },
		"left the team": func(l dynamotest.Local, _ *domain.CoverageSchedule, _ *domain.Receiver) {
			leave(t, l, "cg", "t1")
		},
	} {
		t.Run(name, func(t *testing.T) {
			l, cs, rc := coverageFixture(t)
			mutate(l, &cs, &rc)
			res, err := generate.GenerateCoverage(ctx, l.Stores, cs, rc, now, now)
			if err != nil || !res.Skipped || res.Written != 0 {
				t.Fatalf("%+v %v", res, err)
			}
			if got, _ := l.Stores.Assignments.NotEndedByReceiver(ctx, "r1", now); len(got) != 0 {
				t.Fatalf("wrote: %+v", got)
			}
		})
	}
}

func TestGenerateCoverage_changedWhileRunning(t *testing.T) {
	l, cs, rc := coverageFixture(t)
	ctx := context.Background()
	now := cs.CreatedAt

	// The rule moves to Wednesdays as the first run writes Tuesdays: what it
	// wrote is taken back, and it starts over from the rule as it now is.
	restore := generate.SetAfterWrite(func() {
		changed := cs
		changed.Rule.ByDay, changed.UpdatedAt = []string{"WE"}, now.Add(time.Second)
		if _, err := l.Stores.CoverageSchedules.Update(ctx, changed); err != nil {
			t.Fatal(err)
		}
		generate.SetAfterWrite(nil)
	})
	defer restore()
	res, err := generate.GenerateCoverage(ctx, l.Stores, cs, rc, now, now)
	if err != nil || res.Through != "2026-11-18" {
		t.Fatalf("%+v %v", res, err)
	}
	got, _ := l.Stores.Assignments.NotEndedByReceiver(ctx, "r1", now)
	if len(got) != 2 || got[0].OccurrenceLocal != "2026-11-11" {
		t.Fatalf("after: %+v", got)
	}

	// The caregiver leaves as it writes: it takes everything back.
	cs2 := tuesdays("08:00", "16:00")
	cs2.CoverageScheduleID = "cs2"
	put(t, l, l.Names.CoverageSchedules, cs2)
	generate.SetAfterWrite(func() {
		leave(t, l, "cg", "t1")
	})
	res, err = generate.GenerateCoverage(ctx, l.Stores, cs2, rc, now, now)
	if err != nil || !res.Skipped {
		t.Fatalf("left: %+v %v", res, err)
	}
	if _, err := l.Stores.Assignments.Get(ctx, generate.AssignmentID("cs2", "2026-11-10")); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("not taken back: %v", err)
	}
}

func TestRetimeAssignments(t *testing.T) {
	l, cs, rc := coverageFixture(t)
	ctx := context.Background()
	now := utc("2026-11-10T15:00:00Z") // Tuesday 09:00 in Chicago
	if _, err := generate.GenerateCoverage(ctx, l.Stores, cs, rc, now, now); err != nil {
		t.Fatal(err)
	}
	rc.TimeZone = "America/New_York"
	moved, err := generate.RetimeAssignments(ctx, l.Stores, rc, now)
	if err != nil || moved != 2 {
		t.Fatalf("moved %d %v", moved, err)
	}
	got, _ := l.Stores.Assignments.NotEndedByReceiver(ctx, "r1", now)
	// Today's, under way, stays; the rest keep 08:00–16:00 in the new zone.
	if len(got) != 3 || !got[0].StartsAt.Equal(utc("2026-11-10T14:00:00Z")) ||
		got[1].StartsLocal != "2026-11-17T08:00" || !got[1].StartsAt.Equal(utc("2026-11-17T13:00:00Z")) ||
		!got[1].EndsAt.Equal(utc("2026-11-17T21:00:00Z")) {
		t.Fatalf("after: %+v", got)
	}
	if moved, _ := generate.RetimeAssignments(ctx, l.Stores, rc, now); moved != 0 {
		t.Fatalf("repeat moved %d", moved)
	}
}

func TestDeleteFutureCoverage_findsRowsTheIndexHasNotCaughtUpWith(t *testing.T) {
	l, cs, rc := coverageFixture(t)
	ctx := context.Background()
	now := cs.CreatedAt
	if _, err := generate.GenerateCoverage(ctx, l.Stores, cs, rc, now, now); err != nil {
		t.Fatal(err)
	}
	// Stand in for an index lagging the table: the second Tuesday is filed
	// under another rule there, so only its id can find it.
	lagging, _ := l.Stores.Assignments.Get(ctx, generate.AssignmentID("cs1", "2026-11-17"))
	lagging.CoverageScheduleID = "elsewhere"
	put(t, l, l.Names.Assignments, lagging)

	n, err := generate.DeleteFutureCoverage(ctx, l.Stores, cs, rc, now)
	if err != nil || n != 2 {
		t.Fatalf("deleted %d %v", n, err)
	}
	if got, _ := l.Stores.Assignments.NotEndedByReceiver(ctx, "r1", now); len(got) != 0 {
		t.Fatalf("left: %+v", got)
	}
}
