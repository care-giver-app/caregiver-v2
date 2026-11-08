package domain

import (
	"fmt"
	"strings"
)

// weekdays is the rule's by_day vocabulary in week order, with the short name
// a derived schedule name uses.
var weekdays = []struct{ code, short string }{
	{"MO", "Mon"}, {"TU", "Tue"}, {"WE", "Wed"}, {"TH", "Thu"}, {"FR", "Fri"}, {"SA", "Sat"}, {"SU", "Sun"},
}

// ScheduleName is the schedule's label, or a name derived from its rule and
// time when it has none (the PRD's Tracker schedule).
func ScheduleName(s Schedule) string {
	if label := strings.TrimSpace(s.Label); label != "" {
		return label
	}
	return DeriveScheduleName(s.Rule, s.Time)
}

// DeriveScheduleName names a schedule from its rule and local HH:MM time:
// "Mon, Wed, Fri at 8:00 AM", "Every day at 9:00 PM", and for an interval
// above one week a prefix such as "Every 2 weeks: Mon at 8:00 AM". Days read
// in week order whatever order the rule lists them in.
func DeriveScheduleName(r Rule, hhmm string) string {
	on := make(map[string]bool, len(r.ByDay))
	for _, d := range r.ByDay {
		on[d] = true
	}
	var days []string
	for _, d := range weekdays {
		if on[d.code] {
			days = append(days, d.short)
		}
	}
	when := strings.Join(days, ", ")
	if len(days) == len(weekdays) {
		when = "Every day"
	}
	name := when + " at " + clockTime(hhmm)
	if r.Interval > 1 {
		if len(days) == len(weekdays) {
			name = "every day at " + clockTime(hhmm)
		}
		name = fmt.Sprintf("Every %d weeks: %s", r.Interval, name)
	}
	return name
}

// clockTime turns "08:00" into "8:00 AM" and "21:30" into "9:30 PM". A time
// that is not HH:MM is returned as it is.
func clockTime(hhmm string) string {
	var h, m int
	if n, err := fmt.Sscanf(hhmm, "%2d:%2d", &h, &m); err != nil || n != 2 || len(hhmm) != 5 || h > 23 || m > 59 {
		return hhmm
	}
	suffix := "AM"
	if h >= 12 {
		suffix = "PM"
	}
	if h = h % 12; h == 0 {
		h = 12
	}
	return fmt.Sprintf("%d:%02d %s", h, m, suffix)
}
