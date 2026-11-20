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

// This file materializes coverage schedules as assignments, the way the rest
// of the package materializes tracker schedules as scheduled entries, to the
// same Horizon and with the same reading of local times.
//
// A slot is one date the rule falls on. It starts at start_time that day and
// ends at end_time the same day, or the next day when end_time is at or before
// start_time (an overnight rule). Its occurrence_local is that date,
// YYYY-MM-DD, and its assignment id is a UUID v5 of the rule and that date: a
// rule has at most one slot a day, so the date names the slot even when the
// rule's hours change. That is what keeps a Tuesday an admin handed to someone
// else theirs when the rule is later redrawn with a later start — the redrawn
// Tuesday has the same id as the one already there, and is not made again.

// AssignmentNamespace is the UUID namespace of generated assignment ids. It is
// fixed for good: changing it would make every re-run write a second copy of
// each slot.
var AssignmentNamespace = uuid.MustParse("fc2c46ee-4974-43f1-861a-9f84c2228fd3")

// AssignmentID is the id of the assignment filling one slot of a coverage
// schedule: a UUID v5 of the rule's id and the slot's local date.
func AssignmentID(coverageScheduleID, occurrenceLocal string) string {
	return uuid.NewSHA1(AssignmentNamespace, []byte(coverageScheduleID+"/"+occurrenceLocal)).String()
}

// ResolveLocal is the instant of a local YYYY-MM-DDTHH:MM in loc, read the way
// every occurrence is: the first of two when it happens twice, and with the
// offset before the gap when it never happens.
func ResolveLocal(local string, loc *time.Location) (time.Time, error) {
	wall, err := time.Parse(LocalFormat, local)
	if err != nil {
		return time.Time{}, err
	}
	return resolve(wall.Year(), wall.Month(), wall.Day(), wall.Hour(), wall.Minute(), loc).UTC(), nil
}

// Slot is one span a coverage schedule covers.
type Slot struct {
	Date        string // YYYY-MM-DD, the local date it starts on: its occurrence_local
	StartsLocal string
	EndsLocal   string
	StartsAt    time.Time
	EndsAt      time.Time
}

// ExpandCoverage lists the rule's slots that end after from, in order: one
// already under way at from, then those starting at or after it through
// Horizon past now, plus the first one beyond when none fall within it. It is
// Expand's rule, starting each slot at start_time.
func ExpandCoverage(cs domain.CoverageSchedule, loc *time.Location, from, now time.Time) ([]Slot, error) {
	sc := domain.Schedule{
		ScheduleID: cs.CoverageScheduleID, Rule: cs.Rule, Time: cs.StartTime, StartsOn: cs.StartsOn, EndsOn: cs.EndsOn,
	}
	var eh, em int
	if _, err := fmt.Sscanf(cs.EndTime, "%2d:%2d", &eh, &em); err != nil || len(cs.EndTime) != 5 {
		return nil, fmt.Errorf("coverage schedule %s: end_time %q is not HH:MM", cs.CoverageScheduleID, cs.EndTime)
	}
	overnight := cs.EndTime <= cs.StartTime
	slot := func(o Occurrence) (Slot, bool) {
		day, _ := time.Parse(time.DateOnly, o.Date)
		if overnight {
			day = day.AddDate(0, 0, 1)
		}
		end := resolve(day.Year(), day.Month(), day.Day(), eh, em, loc).UTC()
		s := Slot{
			Date: o.Date, StartsLocal: o.Local, EndsLocal: day.Format(time.DateOnly) + "T" + cs.EndTime,
			StartsAt: o.At, EndsAt: end,
		}
		// A slot the clocks changing squeeze to nothing is not one.
		return s, end.After(o.At)
	}

	// A slot lasts under a day, so one under way at from began within the
	// day before it.
	earlier, err := Expand(sc, loc, from.Add(-24*time.Hour), now)
	if err != nil {
		return nil, err
	}
	var out []Slot
	for _, o := range earlier {
		if !o.At.Before(from) {
			break
		}
		if s, ok := slot(o); ok && s.EndsAt.After(from) {
			out = append(out, s)
		}
	}
	occs, err := Expand(sc, loc, from, now)
	if err != nil {
		return nil, err
	}
	for _, o := range occs {
		if s, ok := slot(o); ok {
			out = append(out, s)
		}
	}
	return out, nil
}

// Assignments turns slots into the assignments the generator writes: the
// rule's caregiver on each, made at now by whoever made the rule.
func Assignments(cs domain.CoverageSchedule, slots []Slot, now time.Time) []domain.Assignment {
	out := make([]domain.Assignment, 0, len(slots))
	for _, s := range slots {
		out = append(out, domain.Assignment{
			AssignmentID: AssignmentID(cs.CoverageScheduleID, s.Date), ReceiverID: cs.ReceiverID, TeamID: cs.TeamID,
			UserID: cs.UserID, StartsLocal: s.StartsLocal, EndsLocal: s.EndsLocal, StartsAt: s.StartsAt, EndsAt: s.EndsAt,
			CoverageScheduleID: cs.CoverageScheduleID, OccurrenceLocal: s.Date, Status: domain.AssignmentActive,
			CreatedBy: cs.CreatedBy, CreatedAt: now,
		})
	}
	return out
}

// coverageCurrent is a coverage schedule, its receiver and team, and whether
// its caregiver is still on the team, as last read.
type coverageCurrent struct {
	cs     domain.CoverageSchedule
	rc     domain.Receiver
	team   domain.Team
	member bool
	gone   bool // the rule, receiver or team no longer exists
}

// live reports whether the rule should still be generating: not removed, its
// receiver not archived, its team not closed, and its caregiver still on it.
func (c coverageCurrent) live() bool {
	return !c.gone && c.cs.RemovedAt == nil && c.rc.Status != domain.ReceiverArchived &&
		c.team.Status != domain.TeamArchived && c.member
}

func isMember(ctx context.Context, s *store.Stores, userID, teamID string) (bool, error) {
	_, err := s.Memberships.Get(ctx, userID, teamID)
	if errors.Is(err, store.ErrNotFound) {
		return false, nil
	}
	return err == nil, err
}

func rereadCoverage(ctx context.Context, s *store.Stores, cs domain.CoverageSchedule) (coverageCurrent, error) {
	var c coverageCurrent
	var err error
	if c.cs, err = s.CoverageSchedules.Get(ctx, cs.CoverageScheduleID); err == nil {
		if c.rc, err = s.Receivers.Get(ctx, cs.ReceiverID); err == nil {
			if c.team, err = s.Teams.Get(ctx, cs.TeamID); err == nil {
				c.member, err = isMember(ctx, s, c.cs.UserID, cs.TeamID)
			}
		}
	}
	if errors.Is(err, store.ErrNotFound) {
		return coverageCurrent{gone: true}, nil
	}
	return c, err
}

// GenerateCoverage writes the rule's slots that end after from (through
// Horizon past now, and at least the next one) as assignments, then records
// generated_through: the local date of the last slot. Each write is
// conditional on the id not existing, so a re-run never duplicates a slot, and
// never remakes one an admin changed or removed by hand. It does nothing for a
// removed rule, an archived receiver, a caregiver no longer on the team, or a
// rule that ended before today; and takes back what it wrote for a closed
// team.
//
// Like Generate, it re-reads the rule, receiver, team and membership once
// written: if any has stopped it, it takes back what it wrote and reports
// Skipped; if the rule or the receiver's time zone changed, it takes it back
// and starts over from them as they now are.
func GenerateCoverage(ctx context.Context, s *store.Stores, cs domain.CoverageSchedule, rc domain.Receiver, from, now time.Time) (Result, error) {
	for attempt := 1; ; attempt++ {
		res, fresh, err := generateCoverageOnce(ctx, s, cs, rc, from, now)
		if err != nil || fresh == nil {
			return res, err
		}
		if attempt == maxAttempts {
			return Result{}, fmt.Errorf("coverage schedule %s changed during each of %d attempts to generate it", cs.CoverageScheduleID, maxAttempts)
		}
		cs, rc = fresh.cs, fresh.rc
	}
}

func generateCoverageOnce(ctx context.Context, s *store.Stores, cs domain.CoverageSchedule, rc domain.Receiver, from, now time.Time) (Result, *coverageCurrent, error) {
	if cs.RemovedAt != nil || rc.Status == domain.ReceiverArchived {
		return Result{Skipped: true}, nil, nil
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		return Result{}, nil, fmt.Errorf("receiver %s time zone: %w", rc.ReceiverID, err)
	}
	if cs.EndsOn != "" && cs.EndsOn < now.In(loc).Format(time.DateOnly) {
		return Result{Skipped: true}, nil, nil
	}
	if ok, err := isMember(ctx, s, cs.UserID, cs.TeamID); err != nil || !ok {
		return Result{Skipped: err == nil}, nil, err
	}
	slots, err := ExpandCoverage(cs, loc, from, now)
	if err != nil {
		return Result{}, nil, err
	}
	var res Result
	var written []string
	for _, a := range Assignments(cs, slots, now) {
		created, err := s.Assignments.CreateIfAbsent(ctx, a)
		if err != nil {
			return res, nil, err
		}
		if created {
			res.Written++
			written = append(written, a.AssignmentID)
		} else {
			res.Present++
		}
	}
	if afterWrite != nil {
		afterWrite()
	}
	cur, err := rereadCoverage(ctx, s, cs)
	if err != nil {
		return res, nil, err
	}
	if cur.live() && cur.cs.UpdatedAt.Equal(cs.UpdatedAt) && cur.rc.TimeZone == rc.TimeZone {
		if len(slots) == 0 {
			return res, nil, nil
		}
		res.Through = slots[len(slots)-1].Date
		err := s.CoverageSchedules.SetGeneratedThrough(ctx, cs.CoverageScheduleID, res.Through, cs.UpdatedAt)
		if err == nil {
			return res, nil, nil
		}
		if !errors.Is(err, store.ErrNotFound) {
			return res, nil, err
		}
		if cur, err = rereadCoverage(ctx, s, cs); err != nil {
			return res, nil, err
		}
	}
	for _, id := range written {
		if _, err := s.Assignments.DeleteIfAttached(ctx, id); err != nil {
			return res, nil, err
		}
	}
	if cur.live() {
		return Result{}, &cur, nil
	}
	return Result{Skipped: true}, nil, nil
}

// RetimeAssignments re-resolves each of the receiver's assignments that has
// not yet begun in the receiver's time zone as it now stands, keeping its
// local start and end: starts_local and ends_local stay, starts_at and ends_at
// move. One already under way, or past, stays where it is. It is safe to
// repeat, and returns how many moved.
func RetimeAssignments(ctx context.Context, s *store.Stores, rc domain.Receiver, now time.Time) (int, error) {
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		return 0, fmt.Errorf("receiver %s time zone: %w", rc.ReceiverID, err)
	}
	as, err := s.Assignments.NotEndedByReceiver(ctx, rc.ReceiverID, now)
	if err != nil {
		return 0, err
	}
	moved := 0
	for _, a := range as {
		if !a.StartsAt.After(now) {
			continue
		}
		start, err := ResolveLocal(a.StartsLocal, loc)
		if err != nil {
			return moved, fmt.Errorf("assignment %s starts_local %q: %w", a.AssignmentID, a.StartsLocal, err)
		}
		end, err := ResolveLocal(a.EndsLocal, loc)
		if err != nil {
			return moved, fmt.Errorf("assignment %s ends_local %q: %w", a.AssignmentID, a.EndsLocal, err)
		}
		if start.Equal(a.StartsAt) && end.Equal(a.EndsAt) {
			continue
		}
		ok, err := s.Assignments.Retime(ctx, a, start, end)
		if err != nil {
			return moved, err
		}
		if ok {
			moved++
		}
	}
	return moved, nil
}

// DeleteFutureCoverage deletes the rule's assignments that start after now and
// still belong to it — what changing or removing it redraws. It finds them
// two ways: through the coverage-schedule index, and by the ids the rule as
// given (before any change) would have made. The index is eventually
// consistent and may not yet hold rows made a moment ago; the ids are exact
// for every slot the rule makes from now. Ones changed or removed by hand stay.
// It returns how many went.
func DeleteFutureCoverage(ctx context.Context, s *store.Stores, cs domain.CoverageSchedule, rc domain.Receiver, now time.Time) (int, error) {
	n, err := s.Assignments.DeleteFutureForSchedule(ctx, cs.CoverageScheduleID, now)
	if err != nil {
		return n, err
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		return n, fmt.Errorf("receiver %s time zone: %w", rc.ReceiverID, err)
	}
	slots, err := ExpandCoverage(cs, loc, now, now)
	if err != nil {
		return n, err
	}
	for _, sl := range slots {
		if !sl.StartsAt.After(now) {
			continue
		}
		gone, err := s.Assignments.DeleteIfAttached(ctx, AssignmentID(cs.CoverageScheduleID, sl.Date))
		if err != nil {
			return n, err
		}
		if gone {
			n++
		}
	}
	return n, nil
}
