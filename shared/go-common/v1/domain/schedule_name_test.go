package domain

import "testing"

func TestDeriveScheduleName(t *testing.T) {
	all := []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}
	cases := []struct {
		rule Rule
		time string
		want string
	}{
		{Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO", "WE", "FR"}}, "08:00", "Mon, Wed, Fri at 8:00 AM"},
		{Rule{Freq: "weekly", Interval: 1, ByDay: []string{"FR", "MO", "WE"}}, "08:00", "Mon, Wed, Fri at 8:00 AM"},
		{Rule{Freq: "weekly", Interval: 1, ByDay: all}, "21:00", "Every day at 9:00 PM"},
		{Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SU"}}, "00:30", "Sun at 12:30 AM"},
		{Rule{Freq: "weekly", Interval: 1, ByDay: []string{"SA"}}, "12:05", "Sat at 12:05 PM"},
		{Rule{Freq: "weekly", Interval: 2, ByDay: []string{"TU", "TH"}}, "09:15", "Every 2 weeks: Tue, Thu at 9:15 AM"},
		{Rule{Freq: "weekly", Interval: 4, ByDay: []string{"MO"}}, "13:00", "Every 4 weeks: Mon at 1:00 PM"},
		{Rule{Freq: "weekly", Interval: 8, ByDay: all}, "07:00", "Every 8 weeks: every day at 7:00 AM"},
		{Rule{Freq: "weekly", Interval: 0, ByDay: []string{"MO", "MO"}}, "23:59", "Mon at 11:59 PM"},
		{Rule{Freq: "weekly", Interval: 1, ByDay: []string{"MO"}}, "8am", "Mon at 8am"},
	}
	for _, c := range cases {
		if got := DeriveScheduleName(c.rule, c.time); got != c.want {
			t.Errorf("DeriveScheduleName(%+v, %q) = %q, want %q", c.rule, c.time, got, c.want)
		}
	}
}

func TestScheduleName_prefersLabel(t *testing.T) {
	s := Schedule{Label: "  Morning dose ", Rule: Rule{Interval: 1, ByDay: []string{"MO"}}, Time: "08:00"}
	if got := ScheduleName(s); got != "Morning dose" {
		t.Fatalf("got %q", got)
	}
	s.Label = "  "
	if got := ScheduleName(s); got != "Mon at 8:00 AM" {
		t.Fatalf("blank label: got %q", got)
	}
}
