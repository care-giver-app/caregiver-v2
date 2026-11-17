package generate_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
)

func TestRetime_movesOnlyWhatIsStillToCome(t *testing.T) {
	l, sc, tr, rc, now, open := raceFixture(t)
	ctx := context.Background()
	if _, err := generate.Generate(ctx, l.Stores, sc, tr, rc, now, now); err != nil {
		t.Fatal(err)
	}
	// One unrecorded from this morning, and one logged ahead of time: neither moves.
	morningAt := utc("2026-11-08T14:00:00Z") // 08:00 Chicago
	morning := domain.Entry{EntryID: generate.EntryID("s1", "2026-11-08T08:00"), TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1",
		ScheduleID: "s1", OccurrenceLocal: "2026-11-08T08:00", OccurrenceAt: &morningAt, State: domain.EntryScheduled,
		Values: map[string]any{}, CreatedAt: now, TimelineAt: morningAt, OpenAt: &morningAt}
	put(t, l, l.Names.Entries, morning)
	before := open()
	logged := before[1]
	logged.State, logged.OpenAt = domain.EntryLogged, nil
	put(t, l, l.Names.Entries, logged)

	rc.TimeZone = "America/New_York"
	put(t, l, l.Names.Receivers, rc)
	moved, err := generate.Retime(ctx, l.Stores, rc, now)
	if err != nil {
		t.Fatal(err)
	}
	after := open()
	if moved != len(after) || moved == 0 { // every one still to come; the morning and logged ones are not in the window
		t.Fatalf("moved %d of %d", moved, len(after))
	}
	for _, e := range after {
		if e.EntryID == morning.EntryID {
			if !e.OccurrenceAt.Equal(morningAt) {
				t.Fatalf("past entry moved: %+v", e)
			}
			continue
		}
		// 08:00 in New York, the wall-clock time kept.
		if got := e.OccurrenceAt.In(mustLoad(t, "America/New_York")).Format("15:04"); got != "08:00" ||
			!e.TimelineAt.Equal(*e.OccurrenceAt) || !e.OpenAt.Equal(*e.OccurrenceAt) {
			t.Fatalf("not re-resolved: %+v", e)
		}
	}
	if got, _ := l.Stores.Entries.Get(ctx, logged.EntryID); !got.OccurrenceAt.Equal(*logged.OccurrenceAt) {
		t.Fatalf("logged entry moved: %+v", got)
	}
	// A repeat writes nothing.
	if again, err := generate.Retime(ctx, l.Stores, rc, now); err != nil || again != 0 {
		t.Fatalf("repeat: %d %v", again, err)
	}
}

func TestGenerate_timeZoneChangedWhileRunning(t *testing.T) {
	l, sc, tr, rc, now, open := raceFixture(t)
	ctx := context.Background()
	landed := false
	restore := generate.SetAfterWrite(func() {
		if landed {
			return
		}
		landed = true
		moved := rc
		moved.TimeZone = "America/New_York"
		put(t, l, l.Names.Receivers, moved)
	})
	_, err := generate.Generate(ctx, l.Stores, sc, tr, rc, now, now)
	restore()
	if err != nil {
		t.Fatal(err)
	}
	ny := mustLoad(t, "America/New_York")
	for _, e := range open() {
		if got := e.OccurrenceAt.In(ny).Format("15:04"); got != "08:00" {
			t.Fatalf("written in the old zone: %s %+v", got, e)
		}
	}
}

func mustLoad(t *testing.T, name string) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation(name)
	if err != nil {
		t.Fatal(err)
	}
	return loc
}
