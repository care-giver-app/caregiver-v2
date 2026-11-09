// Package generate materializes a tracker schedule's occurrences as scheduled
// entries (docs/adr/0012-*, "The generator"). Expand and Entries are pure;
// Generate writes what they produce through the stores. The schedule endpoints
// call it when a schedule is added, changed, or its tracker resumed, and the
// daily job calls it for every live schedule.
//
// Times. A schedule's rule, time, starts_on and ends_on are wall-clock values in
// the receiver's IANA zone, and each occurrence keeps its wall-clock time across
// daylight saving changes. A local time that does not exist (the hour skipped
// when clocks spring forward) is read with the offset in force before the gap,
// so 02:30 on the day Chicago springs forward is 03:30 CDT, as RFC 5545 reads
// it. A local time that happens twice (the hour repeated when clocks fall
// back) is the first of the two.
package generate

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Horizon is how far past now occurrences are written. The next occurrence is
// always written as well, however far beyond the horizon it falls, because
// Coming up shows each tracker's next scheduled entry.
const Horizon = 14 * 24 * time.Hour

// LocalFormat is an occurrence's local date and time, as occurrence_local
// stores it.
const LocalFormat = "2006-01-02T15:04"

// EntryNamespace is the UUID namespace of generated entry ids. It is fixed for
// good: changing it would make every re-run write a second copy of each
// occurrence.
var EntryNamespace = uuid.MustParse("aa10a841-1080-4f97-9b7a-97363faea11b")

// EntryID is the id of the entry for one occurrence of a schedule: a UUID v5 of
// the schedule id and the occurrence's local date and time, so generating the
// same occurrence twice names the same row.
func EntryID(scheduleID, occurrenceLocal string) string {
	return uuid.NewSHA1(EntryNamespace, []byte(scheduleID+"/"+occurrenceLocal)).String()
}

// Occurrence is one time a schedule falls due.
type Occurrence struct {
	Local string    // YYYY-MM-DDTHH:MM in the receiver's zone
	Date  string    // YYYY-MM-DD, the local date
	At    time.Time // the instant, in UTC
}

var weekdayIndex = map[string]int{"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}

// mondayIndex is t's weekday counted from Monday = 0.
func mondayIndex(t time.Time) int { return (int(t.Weekday()) + 6) % 7 }

// Expand lists the schedule's occurrences at or after from, in order, through
// Horizon past now, plus the first one beyond it when none fall within it. A
// weekly rule falls on its by_day weekdays in every interval-th week, counted
// from the Monday-start week holding starts_on; nothing falls before starts_on
// or after ends_on (inclusive).
func Expand(sc domain.Schedule, loc *time.Location, from, now time.Time) ([]Occurrence, error) {
	if sc.Rule.Freq != domain.FreqWeekly || sc.Rule.Interval < 1 {
		return nil, fmt.Errorf("schedule %s: unsupported rule %+v", sc.ScheduleID, sc.Rule)
	}
	days := make([]bool, 7)
	some := false
	for _, d := range sc.Rule.ByDay {
		i, ok := weekdayIndex[d]
		if !ok {
			return nil, fmt.Errorf("schedule %s: unknown weekday %q", sc.ScheduleID, d)
		}
		days[i], some = true, true
	}
	if !some {
		return nil, nil
	}
	var hour, minute int
	if _, err := fmt.Sscanf(sc.Time, "%2d:%2d", &hour, &minute); err != nil || len(sc.Time) != 5 {
		return nil, fmt.Errorf("schedule %s: time %q is not HH:MM", sc.ScheduleID, sc.Time)
	}
	// Dates are civil days, held as midnight UTC so day arithmetic is exact.
	startsOn, err := time.Parse(time.DateOnly, sc.StartsOn)
	if err != nil {
		return nil, fmt.Errorf("schedule %s: starts_on: %w", sc.ScheduleID, err)
	}
	var endsOn *time.Time
	if sc.EndsOn != "" {
		e, err := time.Parse(time.DateOnly, sc.EndsOn)
		if err != nil {
			return nil, fmt.Errorf("schedule %s: ends_on: %w", sc.ScheduleID, err)
		}
		endsOn = &e
	}
	anchor := startsOn.AddDate(0, 0, -mondayIndex(startsOn)) // week 0's Monday
	horizon := now.Add(Horizon)

	// Start the day before from's local date: a resolved instant can sit on
	// either side of midnight only by the DST shift, and the at-or-after-from
	// check below settles it.
	fl := from.In(loc)
	day := time.Date(fl.Year(), fl.Month(), fl.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, -1)
	if day.Before(startsOn) {
		day = startsOn
	}
	period := 7 * sc.Rule.Interval
	var out []Occurrence
	for {
		if endsOn != nil && day.After(*endsOn) {
			return out, nil
		}
		offset := int(day.Sub(anchor).Hours() / 24)
		if week := offset / 7; week%sc.Rule.Interval != 0 {
			// Jump to the Monday of the next week the rule falls in.
			day = anchor.AddDate(0, 0, (week/sc.Rule.Interval+1)*period)
			continue
		}
		if days[mondayIndex(day)] {
			at := resolve(day.Year(), day.Month(), day.Day(), hour, minute, loc)
			if !at.Before(from) {
				if at.After(horizon) && len(out) > 0 {
					return out, nil
				}
				out = append(out, Occurrence{
					Local: fmt.Sprintf("%sT%s", day.Format(time.DateOnly), sc.Time),
					Date:  day.Format(time.DateOnly),
					At:    at.UTC(),
				})
				if at.After(horizon) {
					return out, nil
				}
			}
		}
		day = day.AddDate(0, 0, 1)
	}
}

// resolve is the instant of a wall-clock time in loc: the first of two when it
// happens twice, and read with the offset before the gap when it never happens.
func resolve(y int, m time.Month, d, hour, minute int, loc *time.Location) time.Time {
	wall := time.Date(y, m, d, hour, minute, 0, 0, time.UTC)
	matches := func(t time.Time) bool {
		l := t.In(loc)
		return l.Year() == y && l.Month() == m && l.Day() == d && l.Hour() == hour && l.Minute() == minute
	}
	// The offsets in force a day either side cover both readings of any
	// transition; zones change offset at most once a day.
	_, before := wall.Add(-24 * time.Hour).In(loc).Zone()
	_, after := wall.Add(24 * time.Hour).In(loc).Zone()
	var first *time.Time
	for _, off := range []int{before, after} {
		t := wall.Add(-time.Duration(off) * time.Second)
		if matches(t) && (first == nil || t.Before(*first)) {
			t := t
			first = &t
		}
	}
	if first != nil {
		return *first
	}
	return wall.Add(-time.Duration(before) * time.Second) // in the gap
}

// Entries turns occurrences into the scheduled entries the generator writes:
// the schedule's plan on each, its values pre-filled from planned_values, made
// at now by whoever made the schedule.
func Entries(sc domain.Schedule, occs []Occurrence, now time.Time) []domain.Entry {
	out := make([]domain.Entry, 0, len(occs))
	for _, o := range occs {
		at := o.At
		out = append(out, domain.Entry{
			EntryID: EntryID(sc.ScheduleID, o.Local), TrackerID: sc.TrackerID, ReceiverID: sc.ReceiverID, TeamID: sc.TeamID,
			ScheduleID: sc.ScheduleID, OccurrenceLocal: o.Local, OccurrenceAt: &at,
			PlannedValues: copyValues(sc.PlannedValues), UnrecordedAlert: sc.UnrecordedAlert, GraceMinutes: sc.GraceMinutes,
			State: domain.EntryScheduled, Values: copyValues(sc.PlannedValues),
			CreatedBy: sc.CreatedBy, CreatedAt: now, TimelineAt: at, OpenAt: &at,
		})
	}
	return out
}

func copyValues(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// Result is what one Generate call did.
type Result struct {
	// Skipped is true when nothing was generated because the schedule is
	// removed, its tracker paused, or its receiver archived.
	Skipped bool
	// Written counts the entries created; Present those already there (an
	// earlier run's, or one already logged or skipped), which are left as they are.
	Written, Present int
	// Through is the local date of the last occurrence generated, as stored
	// in generated_through; "" when there was none.
	Through string
}

// Generate writes the schedule's occurrences at or after from (through Horizon
// past now, and at least the next one) as scheduled entries, then records
// generated_through: the local date, YYYY-MM-DD, of the last occurrence it
// generated. When it generates nothing the bookmark is left as it was. Each
// write is conditional on the entry id not existing, so re-runs and concurrent
// runs never duplicate an occurrence and never overwrite one already logged or
// skipped. It does nothing for a removed schedule, a paused tracker, or an
// archived receiver.
func Generate(ctx context.Context, s *store.Stores, sc domain.Schedule, t domain.Tracker, rc domain.Receiver, from, now time.Time) (Result, error) {
	if sc.RemovedAt != nil || t.Status == domain.TrackerPaused || rc.Status == domain.ReceiverArchived {
		return Result{Skipped: true}, nil
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		return Result{}, fmt.Errorf("receiver %s time zone: %w", rc.ReceiverID, err)
	}
	occs, err := Expand(sc, loc, from, now)
	if err != nil {
		return Result{}, err
	}
	var res Result
	for _, e := range Entries(sc, occs, now) {
		created, err := s.Entries.CreateIfAbsent(ctx, e)
		if err != nil {
			return res, err
		}
		if created {
			res.Written++
		} else {
			res.Present++
		}
	}
	if len(occs) == 0 {
		return res, nil
	}
	res.Through = occs[len(occs)-1].Date
	if err := s.Schedules.SetGeneratedThrough(ctx, sc.ScheduleID, res.Through); err != nil {
		if !errors.Is(err, store.ErrNotFound) {
			return res, err
		}
		// Removed while this ran: the removal's own delete may have gone
		// first, so take back what is still waiting.
		_, err := s.Entries.DeleteFutureOpenForSchedule(ctx, sc.ScheduleID, now)
		return Result{Skipped: true}, err
	}
	return res, nil
}
