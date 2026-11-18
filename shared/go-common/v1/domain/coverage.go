package domain

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
)

// CoverageSchedule is a recurring rule that generates assignments for one
// receiver (ADR 0012, Coverage schedule). StartTime and EndTime are local
// HH:MM; an EndTime at or before StartTime runs past midnight into the next
// day. StartsOn/EndsOn are local dates, EndsOn inclusive. A removed rule keeps
// its row (RemovedAt set); GeneratedThrough is the generator's bookmark, the
// local date of the last slot it wrote.
type CoverageSchedule struct {
	CoverageScheduleID string     `dynamodbav:"coverage_schedule_id"`
	ReceiverID         string     `dynamodbav:"receiver_id"`
	TeamID             string     `dynamodbav:"team_id"`
	UserID             string     `dynamodbav:"user_id"`
	Rule               Rule       `dynamodbav:"rule"`
	StartTime          string     `dynamodbav:"start_time"`
	EndTime            string     `dynamodbav:"end_time"`
	StartsOn           string     `dynamodbav:"starts_on"`
	EndsOn             string     `dynamodbav:"ends_on,omitempty"`
	RemovedAt          *time.Time `dynamodbav:"removed_at,omitempty"`
	GeneratedThrough   string     `dynamodbav:"generated_through,omitempty"`
	CreatedBy          string     `dynamodbav:"created_by"`
	CreatedAt          time.Time  `dynamodbav:"created_at"`
	// UpdatedAt is set when the rule is made and on every change to it, so
	// the generator can tell a change landed while it ran.
	UpdatedAt time.Time `dynamodbav:"updated_at"`
}

// AssignmentStatus is whether an assignment stands. Only a generated
// assignment removed by hand is ever removed: the row stays so the generator
// does not make that slot again, and nothing else reads it.
type AssignmentStatus string

const (
	AssignmentActive  AssignmentStatus = "active"
	AssignmentRemoved AssignmentStatus = "removed"
)

// Assignment is one span of time one caregiver is responsible for a receiver
// (ADR 0012, Assignment, amended in the Team endpoints gate). StartsLocal and
// EndsLocal are local YYYY-MM-DDTHH:MM in the receiver's zone; StartsAt and
// EndsAt the instants they resolve to. A generated assignment carries its
// rule's CoverageScheduleID and OccurrenceLocal (the local date of the slot it
// fills); once changed or removed by hand it is DetachedAt, and belongs to no
// rule.
type Assignment struct {
	AssignmentID       string           `dynamodbav:"assignment_id"`
	ReceiverID         string           `dynamodbav:"receiver_id"`
	TeamID             string           `dynamodbav:"team_id"`
	UserID             string           `dynamodbav:"user_id"`
	StartsLocal        string           `dynamodbav:"starts_local"`
	EndsLocal          string           `dynamodbav:"ends_local"`
	StartsAt           time.Time        `dynamodbav:"starts_at"`
	EndsAt             time.Time        `dynamodbav:"ends_at"`
	CoverageScheduleID string           `dynamodbav:"coverage_schedule_id,omitempty"`
	OccurrenceLocal    string           `dynamodbav:"occurrence_local,omitempty"`
	DetachedAt         *time.Time       `dynamodbav:"detached_at,omitempty"`
	Status             AssignmentStatus `dynamodbav:"status"`
	CreatedBy          string           `dynamodbav:"created_by"`
	CreatedAt          time.Time        `dynamodbav:"created_at"`
	UpdatedBy          string           `dynamodbav:"updated_by,omitempty"`
	UpdatedAt          *time.Time       `dynamodbav:"updated_at,omitempty"`
}

// Generated reports whether a coverage schedule made the assignment, detached
// since or not.
func (a Assignment) Generated() bool { return a.CoverageScheduleID != "" }

// RuleID is the coverage schedule the assignment still belongs to: its
// CoverageScheduleID, or "" when made or since changed by hand.
func (a Assignment) RuleID() string {
	if a.DetachedAt != nil {
		return ""
	}
	return a.CoverageScheduleID
}

// ErrInvalidCoverage is wrapped by every assignment and coverage schedule
// validation error, so a handler can map them all to 400 and show err.Error().
var ErrInvalidCoverage = errors.New("invalid coverage")

func invalidCoverage(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalidCoverage, fmt.Sprintf(format, args...))
}

// LocalDateTimeFormat is a local date and time, YYYY-MM-DDTHH:MM, as
// starts_local and ends_local store it.
const LocalDateTimeFormat = "2006-01-02T15:04"

var localDateTimePattern = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}T([01][0-9]|2[0-3]):[0-5][0-9]$`)

// ParseLocalDateTime checks s is a real local YYYY-MM-DDTHH:MM and returns it
// as a wall-clock time held in UTC. name names the field in the error.
func ParseLocalDateTime(name, s string) (time.Time, error) {
	if !localDateTimePattern.MatchString(s) {
		return time.Time{}, invalidCoverage("%s must be YYYY-MM-DDTHH:MM", name)
	}
	t, err := time.Parse(LocalDateTimeFormat, s)
	if err != nil {
		return time.Time{}, invalidCoverage("%s must be YYYY-MM-DDTHH:MM", name)
	}
	return t, nil
}

// CoverageScheduleWrite is what A coverage schedule's Save sends, new or
// changed (the CoverageScheduleWrite schema).
type CoverageScheduleWrite struct {
	UserID    string
	Rule      Rule
	StartTime string
	EndTime   string
	EndsOn    string
}

// ValidateCoverageScheduleWrite checks a coverage schedule's Save. user_id
// must be present (that it names someone on the team is the caller's to
// check). The rule is a weekly rule as a tracker schedule takes. start_time
// and end_time are HH:MM and may not be equal — a slot of no time, or of a
// whole day, is not something the sheet can mean; an end_time before
// start_time runs past midnight. today is the receiver's local date; ends_on
// may not be before it, unless it is storedEndsOn — the ends_on a changed rule
// already has ("" for a new one), sent back as it is.
func ValidateCoverageScheduleWrite(w CoverageScheduleWrite, today, storedEndsOn string) (CoverageScheduleWrite, error) {
	w.UserID = strings.TrimSpace(w.UserID)
	if w.UserID == "" {
		return w, invalidCoverage("user_id is required")
	}
	if err := validateRule(w.Rule); err != nil {
		return w, invalidCoverage("%s", strings.TrimPrefix(err.Error(), ErrInvalidSchedule.Error()+": "))
	}
	if !hhmmPattern.MatchString(w.StartTime) {
		return w, invalidCoverage("start_time must be HH:MM")
	}
	if !hhmmPattern.MatchString(w.EndTime) {
		return w, invalidCoverage("end_time must be HH:MM")
	}
	if w.StartTime == w.EndTime {
		return w, invalidCoverage("end_time must differ from start_time")
	}
	if w.EndsOn != "" {
		if _, err := time.Parse(time.DateOnly, w.EndsOn); err != nil {
			return w, invalidCoverage("ends_on must be a date (YYYY-MM-DD)")
		}
		if w.EndsOn != storedEndsOn && w.EndsOn < today {
			return w, invalidCoverage("ends_on must not be before today")
		}
	}
	return w, nil
}

// ValidateAssignmentSpan checks a resolved assignment: it must end after it
// starts, and end after now.
func ValidateAssignmentSpan(startsAt, endsAt, now time.Time) error {
	if !endsAt.After(startsAt) {
		return invalidCoverage("ends_local must be after starts_local")
	}
	if !endsAt.After(now) {
		return invalidCoverage("an assignment must end in the future")
	}
	return nil
}
