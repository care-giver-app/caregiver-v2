package domain

import (
	"errors"
	"strings"
	"testing"
)

func scheduleTracker() Tracker {
	return Tracker{Fields: []Field{
		{FieldID: "dose", Label: "Dose", Type: FieldNumber, Status: FieldActive},
		{FieldID: "note", Label: "Note", Type: FieldText, Status: FieldActive},
		{FieldID: "taken", Label: "Taken", Type: FieldBoolean, Status: FieldActive},
		{FieldID: "when", Label: "When", Type: FieldDatetime, Status: FieldActive},
		{FieldID: "pills", Label: "Pills", Type: FieldChoice, Multiple: true, Status: FieldActive, Options: []ChoiceOption{
			{OptionID: "a", Label: "A", Status: OptionActive}, {OptionID: "b", Label: "B", Status: OptionActive},
			{OptionID: "old", Label: "Old", Status: OptionRetired},
		}},
		{FieldID: "arm", Label: "Arm", Type: FieldChoice, Status: FieldActive, Options: []ChoiceOption{
			{OptionID: "l", Label: "Left", Status: OptionActive}, {OptionID: "r", Label: "Right", Status: OptionActive},
		}},
		{FieldID: "gone", Label: "Gone", Type: FieldNumber, Status: FieldPaused},
	}}
}

func goodWrite() ScheduleWrite {
	return ScheduleWrite{
		Label: "  Morning dose  ", Rule: Rule{Freq: "weekly", Interval: 2, ByDay: []string{"MO", "FR"}}, Time: "08:00",
		EndsOn: "2026-11-08", PlannedValues: map[string]any{
			"dose": 5.0, "note": "with food", "taken": false, "when": "2026-11-08T08:00:00-06:00",
			"pills": []any{"a", "b"}, "arm": []any{"l"},
		},
	}
}

func TestValidateScheduleWrite(t *testing.T) {
	got, err := ValidateScheduleWrite(goodWrite(), scheduleTracker(), "2026-11-08")
	if err != nil || got.Label != "Morning dose" {
		t.Fatalf("good: %+v err=%v", got, err)
	}
	if _, err := ValidateScheduleWrite(ScheduleWrite{Rule: goodWrite().Rule, Time: "23:59", PlannedValues: map[string]any{"arm": []any{}}},
		scheduleTracker(), "2026-11-08"); err != nil {
		t.Fatalf("minimal: %v", err)
	}

	cases := map[string]struct {
		change func(*ScheduleWrite)
		want   string
	}{
		"freq":            {func(w *ScheduleWrite) { w.Rule.Freq = "daily" }, "freq"},
		"interval":        {func(w *ScheduleWrite) { w.Rule.Interval = 0 }, "interval"},
		"no days":         {func(w *ScheduleWrite) { w.Rule.ByDay = nil }, "by_day"},
		"bad day":         {func(w *ScheduleWrite) { w.Rule.ByDay = []string{"MO", "XX"} }, "unknown day"},
		"repeated day":    {func(w *ScheduleWrite) { w.Rule.ByDay = []string{"MO", "MO"} }, "twice"},
		"time":            {func(w *ScheduleWrite) { w.Time = "8:00" }, "HH:MM"},
		"time 24":         {func(w *ScheduleWrite) { w.Time = "24:00" }, "HH:MM"},
		"label":           {func(w *ScheduleWrite) { w.Label = strings.Repeat("é", 101) }, "label"},
		"ends_on":         {func(w *ScheduleWrite) { w.EndsOn = "2026-11-07" }, "before today"},
		"ends_on format":  {func(w *ScheduleWrite) { w.EndsOn = "11/09/2026" }, "ends_on"},
		"no plan":         {func(w *ScheduleWrite) { w.PlannedValues = nil }, "required"},
		"unknown field":   {func(w *ScheduleWrite) { w.PlannedValues["nope"] = 1.0 }, "unknown field"},
		"paused field":    {func(w *ScheduleWrite) { w.PlannedValues["gone"] = 1.0 }, "paused field"},
		"number":          {func(w *ScheduleWrite) { w.PlannedValues["dose"] = "5" }, "a number"},
		"text":            {func(w *ScheduleWrite) { w.PlannedValues["note"] = 1.0 }, "text"},
		"boolean":         {func(w *ScheduleWrite) { w.PlannedValues["taken"] = "yes" }, "true or false"},
		"datetime":        {func(w *ScheduleWrite) { w.PlannedValues["when"] = "tomorrow" }, "date and time"},
		"choice":          {func(w *ScheduleWrite) { w.PlannedValues["pills"] = "a" }, "list of option ids"},
		"choice item":     {func(w *ScheduleWrite) { w.PlannedValues["pills"] = []any{1.0} }, "list of option ids"},
		"retired option":  {func(w *ScheduleWrite) { w.PlannedValues["pills"] = []any{"old"} }, "retired option"},
		"unknown option":  {func(w *ScheduleWrite) { w.PlannedValues["pills"] = []any{"zzz"} }, "unknown or retired"},
		"repeated option": {func(w *ScheduleWrite) { w.PlannedValues["pills"] = []any{"a", "a"} }, "twice"},
		"single choice":   {func(w *ScheduleWrite) { w.PlannedValues["arm"] = []any{"l", "r"} }, "at most one"},
		"null":            {func(w *ScheduleWrite) { w.PlannedValues["dose"] = nil }, "a number"},
	}
	for name, c := range cases {
		w := goodWrite()
		c.change(&w)
		_, err := ValidateScheduleWrite(w, scheduleTracker(), "2026-11-08")
		if !errors.Is(err, ErrInvalidSchedule) || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: %v, want an invalid schedule saying %q", name, err, c.want)
		}
	}
}
