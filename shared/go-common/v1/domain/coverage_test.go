package domain

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func TestValidateCoverageScheduleWrite(t *testing.T) {
	ok := CoverageScheduleWrite{
		UserID: " u1 ", Rule: Rule{Freq: FreqWeekly, Interval: 1, ByDay: []string{"TU"}},
		StartTime: "08:00", EndTime: "16:00",
	}
	got, err := ValidateCoverageScheduleWrite(ok, "2026-11-08", "")
	if err != nil || got.UserID != "u1" {
		t.Fatalf("valid: %+v %v", got, err)
	}
	overnight := ok
	overnight.StartTime, overnight.EndTime = "22:00", "06:00"
	if _, err := ValidateCoverageScheduleWrite(overnight, "2026-11-08", ""); err != nil {
		t.Fatalf("overnight: %v", err)
	}
	cases := map[string]func(w *CoverageScheduleWrite){
		"user_id is required":                func(w *CoverageScheduleWrite) { w.UserID = " " },
		"rule.freq must be weekly":           func(w *CoverageScheduleWrite) { w.Rule.Freq = "daily" },
		"rule.by_day must name at least one": func(w *CoverageScheduleWrite) { w.Rule.ByDay = nil },
		"start_time must be HH:MM":           func(w *CoverageScheduleWrite) { w.StartTime = "8:00" },
		"end_time must be HH:MM":             func(w *CoverageScheduleWrite) { w.EndTime = "24:00" },
		"end_time must differ":               func(w *CoverageScheduleWrite) { w.EndTime = "08:00" },
		"ends_on must be a date":             func(w *CoverageScheduleWrite) { w.EndsOn = "soon" },
		"ends_on must not be before today":   func(w *CoverageScheduleWrite) { w.EndsOn = "2026-11-07" },
	}
	for want, mutate := range cases {
		w := ok
		w.Rule.ByDay = append([]string(nil), ok.Rule.ByDay...)
		mutate(&w)
		_, err := ValidateCoverageScheduleWrite(w, "2026-11-08", "")
		if !errors.Is(err, ErrInvalidCoverage) || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: got %v", want, err)
		}
	}
	// Today is allowed, and a stored past ends_on may be sent back.
	w := ok
	w.EndsOn = "2026-11-08"
	if _, err := ValidateCoverageScheduleWrite(w, "2026-11-08", ""); err != nil {
		t.Fatalf("ends today: %v", err)
	}
	w.EndsOn = "2026-11-01"
	if _, err := ValidateCoverageScheduleWrite(w, "2026-11-08", "2026-11-01"); err != nil {
		t.Fatalf("stored ends_on: %v", err)
	}
}

func TestParseLocalDateTime(t *testing.T) {
	if got, err := ParseLocalDateTime("starts_local", "2026-11-10T08:30"); err != nil || got.Hour() != 8 || got.Minute() != 30 {
		t.Fatalf("got %v %v", got, err)
	}
	for _, bad := range []string{"", "2026-11-10 08:30", "2026-11-10T24:00", "2026-02-30T08:00", "2026-11-10T08:30:00"} {
		if _, err := ParseLocalDateTime("starts_local", bad); !errors.Is(err, ErrInvalidCoverage) {
			t.Errorf("%q: got %v", bad, err)
		}
	}
}

func TestValidateAssignmentSpan(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	if err := ValidateAssignmentSpan(now.Add(-time.Hour), now.Add(time.Hour), now); err != nil {
		t.Fatalf("in progress: %v", err)
	}
	if err := ValidateAssignmentSpan(now.Add(2*time.Hour), now.Add(time.Hour), now); err == nil {
		t.Fatal("ends before it starts")
	}
	if err := ValidateAssignmentSpan(now.Add(-2*time.Hour), now, now); err == nil {
		t.Fatal("ends now")
	}
}

func TestAssignmentRuleID(t *testing.T) {
	a := Assignment{CoverageScheduleID: "cs"}
	if !a.Generated() || a.RuleID() != "cs" {
		t.Fatal("generated")
	}
	at := time.Now()
	a.DetachedAt = &at
	if !a.Generated() || a.RuleID() != "" {
		t.Fatal("detached")
	}
}
