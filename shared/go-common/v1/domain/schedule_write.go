package domain

import (
	"errors"
	"fmt"
	"math"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

// ErrInvalidSchedule is wrapped by every schedule validation error, so a
// handler can map them all to 400 with errors.Is and show err.Error().
var ErrInvalidSchedule = errors.New("invalid schedule")

func invalidSchedule(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalidSchedule, fmt.Sprintf(format, args...))
}

const (
	// FreqWeekly is the only recurrence the rule takes so far.
	FreqWeekly = "weekly"
	// MaxScheduleLabelLength bounds a schedule's label, in characters.
	MaxScheduleLabelLength = 100
)

var hhmmPattern = regexp.MustCompile(`^([01][0-9]|2[0-3]):[0-5][0-9]$`)

// IsWeekday reports whether code is one of the rule's by_day codes (MO … SU).
func IsWeekday(code string) bool {
	for _, d := range weekdays {
		if d.code == code {
			return true
		}
	}
	return false
}

// ScheduleWrite is what A schedule's Save sends, new or changed (the
// NewSchedule and ScheduleWrite schemas, less replace_gap).
type ScheduleWrite struct {
	Label           string
	Rule            Rule
	Time            string
	EndsOn          string
	PlannedValues   map[string]any
	UnrecordedAlert bool
}

// ValidateScheduleWrite checks a schedule's Save against its tracker and
// returns it with the label trimmed. today is the receiver's local date
// (YYYY-MM-DD); ends_on may not be before it, unless it is storedEndsOn — the
// ends_on a changed schedule already has ("" for a new one), which may be past
// by now and is saved again as it is. planned_values must name only the
// tracker's active fields, each with a value of the field's kind: a number for
// a number, a string for text, a bool for a yes/no, an RFC 3339 string for a
// date and time, and a list of distinct active option ids for a choice — at
// most one for a single-answer choice. A field nobody can know ahead is left
// out, not sent as null.
func ValidateScheduleWrite(w ScheduleWrite, t Tracker, today, storedEndsOn string) (ScheduleWrite, error) {
	w.Label = strings.TrimSpace(w.Label)
	if utf8.RuneCountInString(w.Label) > MaxScheduleLabelLength {
		return w, invalidSchedule("label must be at most %d characters", MaxScheduleLabelLength)
	}
	if err := validateRule(w.Rule); err != nil {
		return w, err
	}
	if !hhmmPattern.MatchString(w.Time) {
		return w, invalidSchedule("time must be HH:MM")
	}
	if w.EndsOn != "" {
		if _, err := time.Parse(time.DateOnly, w.EndsOn); err != nil {
			return w, invalidSchedule("ends_on must be a date (YYYY-MM-DD)")
		}
		if w.EndsOn != storedEndsOn && w.EndsOn < today {
			return w, invalidSchedule("ends_on must not be before today")
		}
	}
	if w.PlannedValues == nil {
		return w, invalidSchedule("planned_values is required")
	}
	fields := make(map[string]Field, len(t.Fields))
	for _, f := range t.Fields {
		fields[f.FieldID] = f
	}
	for id, v := range w.PlannedValues {
		f, ok := fields[id]
		if !ok {
			return w, invalidSchedule("planned_values names unknown field %q", id)
		}
		if f.Status != FieldActive {
			return w, invalidSchedule("planned_values names paused field %q", f.Label)
		}
		if err := validatePlannedValue(f, v); err != nil {
			return w, err
		}
	}
	return w, nil
}

func validateRule(r Rule) error {
	if r.Freq != FreqWeekly {
		return invalidSchedule("rule.freq must be weekly")
	}
	if r.Interval < 1 {
		return invalidSchedule("rule.interval must be at least 1")
	}
	if len(r.ByDay) == 0 {
		return invalidSchedule("rule.by_day must name at least one day")
	}
	seen := map[string]bool{}
	for _, d := range r.ByDay {
		if !IsWeekday(d) {
			return invalidSchedule("rule.by_day has unknown day %q", d)
		}
		if seen[d] {
			return invalidSchedule("rule.by_day names %q twice", d)
		}
		seen[d] = true
	}
	return nil
}

// validatePlannedValue checks v is of f's kind. Values arrive JSON-decoded:
// numbers as float64, lists as []any.
func validatePlannedValue(f Field, v any) error {
	wrong := func(kind string) error {
		return invalidSchedule("planned value for %q must be %s", f.Label, kind)
	}
	switch f.Type {
	case FieldNumber:
		n, ok := v.(float64)
		if !ok || math.IsNaN(n) || math.IsInf(n, 0) {
			return wrong("a number")
		}
	case FieldText:
		if _, ok := v.(string); !ok {
			return wrong("text")
		}
	case FieldBoolean:
		if _, ok := v.(bool); !ok {
			return wrong("true or false")
		}
	case FieldDatetime:
		s, ok := v.(string)
		if !ok {
			return wrong("a date and time")
		}
		if _, err := time.Parse(time.RFC3339, s); err != nil {
			return wrong("a date and time")
		}
	case FieldChoice:
		list, ok := v.([]any)
		if !ok {
			return wrong("a list of option ids")
		}
		if !f.Multiple && len(list) > 1 {
			return invalidSchedule("planned value for %q takes at most one option", f.Label)
		}
		active := map[string]bool{}
		for _, o := range f.Options {
			if o.Status == OptionActive {
				active[o.OptionID] = true
			}
		}
		seen := map[string]bool{}
		for _, item := range list {
			id, ok := item.(string)
			if !ok {
				return wrong("a list of option ids")
			}
			if !active[id] {
				return invalidSchedule("planned value for %q names unknown or retired option %q", f.Label, id)
			}
			if seen[id] {
				return invalidSchedule("planned value for %q names option %q twice", f.Label, id)
			}
			seen[id] = true
		}
	default:
		return wrong("a value of a known type")
	}
	return nil
}
