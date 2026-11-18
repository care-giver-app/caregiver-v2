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

func coverageRule(id, receiver, user string, created time.Time) domain.CoverageSchedule {
	return domain.CoverageSchedule{
		CoverageScheduleID: id, ReceiverID: receiver, TeamID: "t1", UserID: user,
		Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"TU"}}, StartTime: "08:00", EndTime: "16:00",
		StartsOn: "2026-11-01", CreatedBy: "admin", CreatedAt: created, UpdatedAt: created,
	}
}

// assignment is an active assignment on r1 from start for hours, made by
// hand unless rule is set.
func assignment(id, user string, start time.Time, hours int, rule string) domain.Assignment {
	a := domain.Assignment{
		AssignmentID: id, ReceiverID: "r1", TeamID: "t1", UserID: user,
		StartsLocal: start.Format(domain.LocalDateTimeFormat), EndsLocal: start.Add(time.Duration(hours) * time.Hour).Format(domain.LocalDateTimeFormat),
		StartsAt: start, EndsAt: start.Add(time.Duration(hours) * time.Hour),
		Status: domain.AssignmentActive, CreatedBy: "admin", CreatedAt: start.Add(-48 * time.Hour),
	}
	if rule != "" {
		a.CoverageScheduleID, a.OccurrenceLocal = rule, start.Format(time.DateOnly)
	}
	return a
}

func TestCoverageSchedule_CRUD(t *testing.T) {
	l := dynamotest.StartLocal(t)
	s := l.Stores.CoverageSchedules
	ctx := context.Background()

	for i, cs := range []domain.CoverageSchedule{
		coverageRule("b", "r1", "u1", now.Add(time.Hour)),
		coverageRule("a", "r1", "u2", now),
		coverageRule("other", "r2", "u1", now),
	} {
		if err := s.Create(ctx, cs); err != nil {
			t.Fatalf("create %d: %v", i, err)
		}
	}
	if err := s.Create(ctx, coverageRule("a", "r1", "u2", now)); err == nil {
		t.Fatal("duplicate create succeeded")
	}
	live, err := s.ListLiveByReceiver(ctx, "r1")
	if err != nil || len(live) != 2 || live[0].CoverageScheduleID != "a" || live[1].CoverageScheduleID != "b" {
		t.Fatalf("live: %+v %v", live, err)
	}

	// Update: new user, hours and end; then clear the end.
	cs := live[0]
	cs.UserID, cs.StartTime, cs.EndTime, cs.EndsOn, cs.UpdatedAt = "u3", "22:00", "06:00", "2026-12-01", now.Add(time.Minute)
	got, err := s.Update(ctx, cs)
	if err != nil || got.UserID != "u3" || got.EndTime != "06:00" || got.EndsOn != "2026-12-01" || got.StartsOn != "2026-11-01" ||
		!got.UpdatedAt.Equal(now.Add(time.Minute)) {
		t.Fatalf("update: %+v %v", got, err)
	}
	cs.EndsOn = ""
	if got, err = s.Update(ctx, cs); err != nil || got.EndsOn != "" {
		t.Fatalf("clear ends_on: %+v %v", got, err)
	}

	// Bookmark only on an unchanged rule.
	if err := s.SetGeneratedThrough(ctx, "a", "2026-11-24", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("stale bookmark: %v", err)
	}
	if err := s.SetGeneratedThrough(ctx, "a", "2026-11-24", now.Add(time.Minute)); err != nil {
		t.Fatalf("bookmark: %v", err)
	}

	// EndOn: sets, never extends.
	if ok, err := s.EndOn(ctx, "a", "2026-11-10", now.Add(2*time.Minute)); !ok || err != nil {
		t.Fatalf("end: %v %v", ok, err)
	}
	if ok, err := s.EndOn(ctx, "a", "2026-11-20", now.Add(3*time.Minute)); ok || err != nil {
		t.Fatalf("extend: %v %v", ok, err)
	}
	if got, _ := s.Get(ctx, "a"); got.EndsOn != "2026-11-10" || !got.UpdatedAt.Equal(now.Add(2*time.Minute)) {
		t.Fatalf("after end: %+v", got)
	}

	// Remove: once; then gone from the live lists, still readable.
	if err := s.MarkRemoved(ctx, "a", now); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkRemoved(ctx, "a", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("repeat remove: %v", err)
	}
	if _, err := s.Update(ctx, cs); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("update removed: %v", err)
	}
	if live, _ := s.ListLiveByReceiver(ctx, "r1"); len(live) != 1 || live[0].CoverageScheduleID != "b" {
		t.Fatalf("live after remove: %+v", live)
	}
	if all, err := s.ListLive(ctx); err != nil || len(all) != 2 {
		t.Fatalf("list live: %+v %v", all, err)
	}
	if got, err := s.Get(ctx, "a"); err != nil || got.RemovedAt == nil {
		t.Fatalf("get removed: %+v %v", got, err)
	}
}

func TestAssignment_NotEndedAndScheduleRedraw(t *testing.T) {
	l := dynamotest.StartLocal(t)
	s := l.Stores.Assignments
	ctx := context.Background()
	detached := now.Add(-time.Hour)

	long := assignment("long", "u1", now.Add(-30*24*time.Hour), 31*24, "") // began a month ago, still running
	past := assignment("past", "u1", now.Add(-10*time.Hour), 2, "cs")
	inProgress := assignment("now", "u2", now.Add(-time.Hour), 3, "cs")
	future := assignment("future", "u1", now.Add(24*time.Hour), 8, "cs")
	handed := assignment("handed", "u3", now.Add(48*time.Hour), 8, "cs")
	handed.DetachedAt = &detached
	removed := assignment("removed", "u1", now.Add(72*time.Hour), 8, "cs")
	removed.DetachedAt, removed.Status = &detached, domain.AssignmentRemoved
	byHand := assignment("byhand", "u2", now.Add(5*time.Hour), 1, "")
	other := assignment("other", "u1", now.Add(time.Hour), 1, "")
	other.ReceiverID = "r2"
	for _, a := range []domain.Assignment{long, past, inProgress, future, handed, removed, byHand, other} {
		if err := s.Create(ctx, a); err != nil {
			t.Fatalf("create %s: %v", a.AssignmentID, err)
		}
	}
	if ok, err := s.CreateIfAbsent(ctx, future); ok || err != nil {
		t.Fatalf("create twice: %v %v", ok, err)
	}

	got, err := s.NotEndedByReceiver(ctx, "r1", now)
	if err != nil {
		t.Fatal(err)
	}
	ids := []string{}
	for _, a := range got {
		ids = append(ids, a.AssignmentID)
	}
	if want := "[long now byhand future handed]"; sprint(ids) != want {
		t.Fatalf("not ended: %v want %s", ids, want)
	}
	if got[3].RuleID() != "cs" || got[4].RuleID() != "" || got[4].CoverageScheduleID != "cs" {
		t.Fatalf("rule ids: %+v %+v", got[3], got[4])
	}

	// Redrawing the rule takes only what is ahead and still its own.
	n, err := s.DeleteFutureForSchedule(ctx, "cs", now)
	if err != nil || n != 1 {
		t.Fatalf("redraw: %d %v", n, err)
	}
	for id, wantErr := range map[string]error{"future": store.ErrNotFound, "handed": nil, "removed": nil, "now": nil, "past": nil} {
		if _, err := s.Get(ctx, id); !errors.Is(err, wantErr) {
			t.Errorf("%s after redraw: %v", id, err)
		}
	}
}

func sprint(ids []string) string {
	out := "["
	for i, id := range ids {
		if i > 0 {
			out += " "
		}
		out += id
	}
	return out + "]"
}

func TestAssignment_ChangeAndRemove(t *testing.T) {
	l := dynamotest.StartLocal(t)
	s := l.Stores.Assignments
	ctx := context.Background()
	gen := assignment("gen", "u1", now.Add(24*time.Hour), 8, "cs")
	hand := assignment("hand", "u1", now.Add(24*time.Hour), 8, "")
	ended := assignment("ended", "u1", now.Add(-8*time.Hour), 8, "cs")
	for _, a := range []domain.Assignment{gen, hand, ended} {
		if err := s.Create(ctx, a); err != nil {
			t.Fatal(err)
		}
	}

	// Handing a generated one to someone else detaches it.
	gen.UserID = "u2"
	got, err := s.Change(ctx, gen, "admin", now)
	if err != nil || got.UserID != "u2" || got.DetachedAt == nil || !got.DetachedAt.Equal(now) || got.UpdatedBy != "admin" ||
		got.CoverageScheduleID != "cs" || got.RuleID() != "" {
		t.Fatalf("change gen: %+v %v", got, err)
	}
	// A hand-made one has nothing to detach from.
	hand.EndsAt = hand.EndsAt.Add(time.Hour)
	if got, err := s.Change(ctx, hand, "admin", now); err != nil || got.DetachedAt != nil || !got.EndsAt.Equal(hand.EndsAt) {
		t.Fatalf("change hand: %+v %v", got, err)
	}
	if _, err := s.Change(ctx, ended, "admin", now); !errors.Is(err, store.ErrAssignmentEnded) {
		t.Fatalf("change ended: %v", err)
	}
	if err := s.Remove(ctx, ended, "admin", now); !errors.Is(err, store.ErrAssignmentEnded) {
		t.Fatalf("remove ended: %v", err)
	}

	// Removing: a hand-made one goes; a generated one stays as removed.
	if err := s.Remove(ctx, hand, "admin", now); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Get(ctx, "hand"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("hand after remove: %v", err)
	}
	if err := s.Remove(ctx, hand, "admin", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("remove hand twice: %v", err)
	}
	if err := s.Remove(ctx, gen, "admin", now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if got, err := s.Get(ctx, "gen"); err != nil || got.Status != domain.AssignmentRemoved || !got.DetachedAt.Equal(now) {
		t.Fatalf("gen after remove: %+v %v", got, err)
	}
	if err := s.Remove(ctx, gen, "admin", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("remove gen twice: %v", err)
	}
	if _, err := s.Change(ctx, gen, "admin", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("change removed: %v", err)
	}
	if ok, err := s.CreateIfAbsent(ctx, assignment("gen", "u1", now.Add(24*time.Hour), 8, "cs")); ok || err != nil {
		t.Fatalf("regenerate removed: %v %v", ok, err)
	}
}

func TestAssignment_RetimeAndEndNow(t *testing.T) {
	l := dynamotest.StartLocal(t)
	s := l.Stores.Assignments
	ctx := context.Background()
	a := assignment("a", "u1", now.Add(24*time.Hour), 8, "cs")
	if err := s.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.Retime(ctx, a, a.StartsAt.Add(time.Hour), a.EndsAt.Add(time.Hour)); !ok || err != nil {
		t.Fatalf("retime: %v %v", ok, err)
	}
	stale := a
	stale.StartsLocal = "2000-01-01T00:00"
	if ok, err := s.Retime(ctx, stale, a.StartsAt, a.EndsAt); ok || err != nil {
		t.Fatalf("retime stale: %v %v", ok, err)
	}
	if got, _ := s.Get(ctx, "a"); !got.StartsAt.Equal(a.StartsAt.Add(time.Hour)) || got.StartsLocal != a.StartsLocal {
		t.Fatalf("after retime: %+v", got)
	}

	running := assignment("running", "u1", now.Add(-time.Hour), 8, "cs")
	if err := s.Create(ctx, running); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.EndNow(ctx, running, "2026-11-08T06:00", "u1", now); !ok || err != nil {
		t.Fatalf("end now: %v %v", ok, err)
	}
	got, _ := s.Get(ctx, "running")
	if !got.EndsAt.Equal(now) || got.EndsLocal != "2026-11-08T06:00" || got.DetachedAt == nil {
		t.Fatalf("after end now: %+v", got)
	}
	if ok, err := s.EndNow(ctx, running, "2026-11-08T06:00", "u1", now); ok || err != nil {
		t.Fatalf("end now twice: %v %v", ok, err)
	}
}

func TestReleaseRoster(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	// now is 06:00 in Chicago on 2026-11-08.
	for _, rc := range []domain.Receiver{
		{ReceiverID: "r1", TeamID: "t1", Name: "Grandma", TimeZone: "America/Chicago", Status: domain.ReceiverActive, CreatedAt: now},
		{ReceiverID: "r-arch", TeamID: "t1", Name: "Gone", TimeZone: "America/Chicago", Status: domain.ReceiverArchived, CreatedAt: now},
	} {
		seed(t, l, l.Names.Receivers, rc)
	}
	mine := coverageRule("mine", "r1", "u1", now)
	endsLater := coverageRule("later", "r-arch", "u1", now)
	endsLater.EndsOn = "2026-12-01"
	endsSooner := coverageRule("sooner", "r1", "u1", now)
	endsSooner.EndsOn = "2026-11-08"
	theirs := coverageRule("theirs", "r1", "u2", now)
	for _, cs := range []domain.CoverageSchedule{mine, endsLater, endsSooner, theirs} {
		if err := l.Stores.CoverageSchedules.Create(ctx, cs); err != nil {
			t.Fatal(err)
		}
	}
	past := assignment("past", "u1", now.Add(-10*time.Hour), 2, "")
	running := assignment("running", "u1", now.Add(-time.Hour), 4, "")
	aheadHand := assignment("ahead-hand", "u1", now.Add(time.Hour), 4, "")
	aheadGen := assignment("ahead-gen", "u1", now.Add(26*time.Hour), 4, "mine")
	someoneElse := assignment("else", "u2", now.Add(time.Hour), 4, "")
	archAhead := assignment("arch", "u1", now.Add(time.Hour), 4, "")
	archAhead.ReceiverID = "r-arch"
	for _, a := range []domain.Assignment{past, running, aheadHand, aheadGen, someoneElse, archAhead} {
		if err := l.Stores.Assignments.Create(ctx, a); err != nil {
			t.Fatal(err)
		}
	}

	if err := l.Stores.ReleaseRoster(ctx, "t1", "u1", now); err != nil {
		t.Fatal(err)
	}
	if err := l.Stores.ReleaseRoster(ctx, "t1", "u1", now); err != nil {
		t.Fatalf("repeat: %v", err)
	}

	for id, wantEnd := range map[string]string{"mine": "2026-11-08", "later": "2026-11-08", "sooner": "2026-11-08", "theirs": ""} {
		got, err := l.Stores.CoverageSchedules.Get(ctx, id)
		if err != nil || got.EndsOn != wantEnd || got.RemovedAt != nil {
			t.Errorf("%s: ends_on=%q %v", id, got.EndsOn, err)
		}
	}
	if got, _ := l.Stores.CoverageSchedules.Get(ctx, "sooner"); !got.UpdatedAt.Equal(now) {
		t.Errorf("sooner was touched: %+v", got)
	}
	a := l.Stores.Assignments
	if got, err := a.Get(ctx, "past"); err != nil || !got.EndsAt.Equal(past.EndsAt) {
		t.Errorf("past: %+v %v", got, err)
	}
	if got, err := a.Get(ctx, "running"); err != nil || !got.EndsAt.Equal(now) || got.EndsLocal != "2026-11-08T06:00" {
		t.Errorf("running: %+v %v", got, err)
	}
	if _, err := a.Get(ctx, "ahead-hand"); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("ahead-hand: %v", err)
	}
	if _, err := a.Get(ctx, "arch"); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("arch: %v", err)
	}
	if got, err := a.Get(ctx, "ahead-gen"); err != nil || got.Status != domain.AssignmentRemoved {
		t.Errorf("ahead-gen: %+v %v", got, err)
	}
	if got, err := a.Get(ctx, "else"); err != nil || got.Status != domain.AssignmentActive {
		t.Errorf("else: %+v %v", got, err)
	}
}
