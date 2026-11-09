package generate_test

import (
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
)

func chicago(t *testing.T) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation("America/Chicago")
	if err != nil {
		t.Fatal(err)
	}
	return loc
}

func utc(s string) time.Time {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		panic(err)
	}
	return t
}

var everyDay = []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}

func TestExpand(t *testing.T) {
	loc := chicago(t)
	// Sunday 8 November 2026, noon in Chicago (CST, UTC-6).
	now := utc("2026-11-08T18:00:00Z")
	type tc struct {
		name     string
		rule     domain.Rule
		hhmm     string
		startsOn string
		endsOn   string
		from     time.Time
		now      time.Time
		want     []string // occurrence_local, in order
	}
	cases := []tc{
		{name: "every day, saved after today's time: today's is not made",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, hhmm: "08:00", startsOn: "2026-11-08",
			want: []string{
				"2026-11-09T08:00", "2026-11-10T08:00", "2026-11-11T08:00", "2026-11-12T08:00", "2026-11-13T08:00",
				"2026-11-14T08:00", "2026-11-15T08:00", "2026-11-16T08:00", "2026-11-17T08:00", "2026-11-18T08:00",
				"2026-11-19T08:00", "2026-11-20T08:00", "2026-11-21T08:00", "2026-11-22T08:00",
			}},
		{name: "saved before today's time: today's is made, and the horizon ends at now plus 14 days",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SU"}}, hhmm: "13:00", startsOn: "2026-11-08",
			want: []string{"2026-11-08T13:00", "2026-11-15T13:00"}},
		{name: "at exactly from is made",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SU"}}, hhmm: "12:00", startsOn: "2026-11-08",
			want: []string{"2026-11-08T12:00", "2026-11-15T12:00", "2026-11-22T12:00"}},
		{name: "several weekdays",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"FR", "MO", "WE"}}, hhmm: "20:00", startsOn: "2026-11-08",
			want: []string{"2026-11-09T20:00", "2026-11-11T20:00", "2026-11-13T20:00", "2026-11-16T20:00", "2026-11-18T20:00", "2026-11-20T20:00"}},
		{name: "every 2 weeks counts from the week holding starts_on",
			rule: domain.Rule{Freq: "weekly", Interval: 2, ByDay: []string{"MO"}}, hhmm: "08:00", startsOn: "2026-11-08",
			want: []string{"2026-11-16T08:00"}},
		{name: "every 2 weeks from a start in the past keeps its phase",
			rule: domain.Rule{Freq: "weekly", Interval: 2, ByDay: []string{"MO", "TH"}}, hhmm: "08:00", startsOn: "2026-10-26",
			want: []string{"2026-11-09T08:00", "2026-11-12T08:00"}},
		{name: "every 4 weeks: the next one beyond the horizon is still made",
			rule: domain.Rule{Freq: "weekly", Interval: 4, ByDay: []string{"MO"}}, hhmm: "08:00", startsOn: "2026-11-08",
			want: []string{"2026-11-30T08:00"}},
		{name: "every 8 weeks: only the next one",
			rule: domain.Rule{Freq: "weekly", Interval: 8, ByDay: []string{"MO", "TU"}}, hhmm: "08:00", startsOn: "2026-11-08",
			want: []string{"2026-12-28T08:00"}},
		{name: "nothing before starts_on in its own week",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO", "TU"}}, hhmm: "08:00", startsOn: "2026-11-17",
			want: []string{"2026-11-17T08:00"}},
		{name: "ends_on is inclusive",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, hhmm: "08:00", startsOn: "2026-11-08", endsOn: "2026-11-10",
			want: []string{"2026-11-09T08:00", "2026-11-10T08:00"}},
		{name: "ends_on today after today's time: nothing",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, hhmm: "08:00", startsOn: "2026-11-01", endsOn: "2026-11-08"},
		{name: "ends_on in the past: nothing",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, hhmm: "08:00", startsOn: "2026-11-01", endsOn: "2026-11-07"},
		{name: "ends_on before the next of a long interval: nothing",
			rule: domain.Rule{Freq: "weekly", Interval: 8, ByDay: []string{"MO"}}, hhmm: "08:00", startsOn: "2026-11-08", endsOn: "2026-12-01"},
		{name: "from later than now (the daily job resuming past its bookmark)",
			rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, hhmm: "08:00", startsOn: "2026-11-01",
			from: utc("2026-11-21T00:00:00Z"),
			want: []string{"2026-11-21T08:00", "2026-11-22T08:00"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			sc := domain.Schedule{ScheduleID: "s1", Rule: c.rule, Time: c.hhmm, StartsOn: c.startsOn, EndsOn: c.endsOn}
			from, n := c.from, c.now
			if n.IsZero() {
				n = now
			}
			if from.IsZero() {
				from = n
			}
			got, err := generate.Expand(sc, loc, from, n)
			if err != nil {
				t.Fatal(err)
			}
			var locals []string
			for _, o := range got {
				locals = append(locals, o.Local)
				if o.Date != o.Local[:10] {
					t.Errorf("%s: date %q", o.Local, o.Date)
				}
				if l := o.At.In(loc).Format(generate.LocalFormat); l != o.Local {
					t.Errorf("%s: instant %s reads %s locally", o.Local, o.At, l)
				}
			}
			if len(locals) != len(c.want) {
				t.Fatalf("got %v, want %v", locals, c.want)
			}
			for i := range locals {
				if locals[i] != c.want[i] {
					t.Fatalf("got %v, want %v", locals, c.want)
				}
			}
		})
	}
}

func TestExpand_daylightSaving(t *testing.T) {
	loc := chicago(t)
	at := func(sc domain.Schedule, now time.Time) []generate.Occurrence {
		t.Helper()
		occs, err := generate.Expand(sc, loc, now, now)
		if err != nil {
			t.Fatal(err)
		}
		return occs
	}

	// Chicago springs forward at 02:00 on Sunday 14 March 2027.
	spring := utc("2027-03-12T18:00:00Z")
	daily := domain.Schedule{Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, Time: "08:00", StartsOn: "2027-03-12"}
	occs := at(daily, spring)
	if occs[0].Local != "2027-03-13T08:00" || !occs[0].At.Equal(utc("2027-03-13T14:00:00Z")) ||
		occs[1].Local != "2027-03-14T08:00" || !occs[1].At.Equal(utc("2027-03-14T13:00:00Z")) {
		t.Fatalf("08:00 across spring forward keeps its wall clock: %+v", occs[:2])
	}

	// 02:30 does not exist that day: it is read with the offset before the gap (CST), so 03:30 CDT.
	gap := domain.Schedule{Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SU"}}, Time: "02:30", StartsOn: "2027-03-12"}
	occs = at(gap, spring)
	if occs[0].Local != "2027-03-14T02:30" || !occs[0].At.Equal(utc("2027-03-14T08:30:00Z")) {
		t.Fatalf("nonexistent 02:30: %+v", occs[0])
	}
	if occs[1].Local != "2027-03-21T02:30" || !occs[1].At.Equal(utc("2027-03-21T07:30:00Z")) {
		t.Fatalf("02:30 the week after: %+v", occs[1])
	}

	// Chicago falls back at 02:00 on Sunday 7 November 2027: 01:30 happens twice; the first (CDT) is taken.
	fall := utc("2027-11-05T18:00:00Z")
	twice := domain.Schedule{Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SU"}}, Time: "01:30", StartsOn: "2027-11-05"}
	occs = at(twice, fall)
	if occs[0].Local != "2027-11-07T01:30" || !occs[0].At.Equal(utc("2027-11-07T06:30:00Z")) {
		t.Fatalf("ambiguous 01:30: %+v", occs[0])
	}
	if !occs[1].At.Equal(utc("2027-11-14T07:30:00Z")) {
		t.Fatalf("01:30 the week after, in CST: %+v", occs[1])
	}
	daily.StartsOn = "2027-11-05"
	occs = at(daily, fall)
	if !occs[0].At.Equal(utc("2027-11-06T13:00:00Z")) || !occs[1].At.Equal(utc("2027-11-07T14:00:00Z")) {
		t.Fatalf("08:00 across fall back keeps its wall clock: %+v", occs[:2])
	}
}

func TestExpand_rejectsBadSchedules(t *testing.T) {
	loc := chicago(t)
	now := utc("2026-11-08T18:00:00Z")
	for name, sc := range map[string]domain.Schedule{
		"freq":     {Rule: domain.Rule{Freq: "daily", Interval: 1, ByDay: everyDay}, Time: "08:00", StartsOn: "2026-11-08"},
		"interval": {Rule: domain.Rule{Freq: "weekly", Interval: 0, ByDay: everyDay}, Time: "08:00", StartsOn: "2026-11-08"},
		"day":      {Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: []string{"XX"}}, Time: "08:00", StartsOn: "2026-11-08"},
		"time":     {Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, Time: "8am", StartsOn: "2026-11-08"},
		"starts":   {Rule: domain.Rule{Freq: "weekly", Interval: 1, ByDay: everyDay}, Time: "08:00", StartsOn: "today"},
	} {
		if _, err := generate.Expand(sc, loc, now, now); err == nil {
			t.Errorf("%s: want an error", name)
		}
	}
}

func TestEntryID_isDeterministic(t *testing.T) {
	a := generate.EntryID("sched-1", "2026-11-09T08:00")
	if a != generate.EntryID("sched-1", "2026-11-09T08:00") {
		t.Fatal("same occurrence, different ids")
	}
	if a == generate.EntryID("sched-1", "2026-11-10T08:00") || a == generate.EntryID("sched-2", "2026-11-09T08:00") {
		t.Fatal("different occurrences share an id")
	}
	// Pinned: a changed namespace or name would duplicate every occurrence on the next run.
	if a != "bdded9fd-7c72-53c3-b85a-c68207e92520" {
		t.Fatalf("EntryID(sched-1, 2026-11-09T08:00) = %s, which is not the id earlier runs wrote", a)
	}
}

func TestEntries(t *testing.T) {
	now := utc("2026-11-08T18:00:00Z")
	sc := domain.Schedule{
		ScheduleID: "s1", TrackerID: "tr1", ReceiverID: "r1", TeamID: "t1", CreatedBy: "admin",
		PlannedValues: map[string]any{"dose": 5.0}, UnrecordedAlert: true,
	}
	occ := generate.Occurrence{Local: "2026-11-09T08:00", Date: "2026-11-09", At: utc("2026-11-09T14:00:00Z")}
	es := generate.Entries(sc, []generate.Occurrence{occ}, now)
	if len(es) != 1 {
		t.Fatalf("entries: %+v", es)
	}
	e := es[0]
	if e.EntryID != generate.EntryID("s1", occ.Local) || e.TrackerID != "tr1" || e.ReceiverID != "r1" || e.TeamID != "t1" ||
		e.ScheduleID != "s1" || e.State != domain.EntryScheduled || e.OccurrenceLocal != occ.Local ||
		!e.OccurrenceAt.Equal(occ.At) || !e.OpenAt.Equal(occ.At) || !e.TimelineAt.Equal(occ.At) ||
		e.PlannedValues["dose"] != 5.0 || e.Values["dose"] != 5.0 || !e.UnrecordedAlert ||
		e.CreatedBy != "admin" || !e.CreatedAt.Equal(now) {
		t.Fatalf("entry: %+v", e)
	}
	e.Values["dose"] = 6.0
	if e.PlannedValues["dose"] != 5.0 || sc.PlannedValues["dose"] != 5.0 {
		t.Fatal("values share a map with the plan")
	}
}
