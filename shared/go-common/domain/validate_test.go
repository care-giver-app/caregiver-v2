package domain

import "testing"

func bpFields() []Field {
	max140 := 140.0
	return []Field{
		{Key: "systolic", Label: "Systolic", Type: FieldNumber, Required: true, Threshold: &Threshold{Max: &max140}},
		{Key: "mood", Label: "Mood", Type: FieldEnum, Options: []string{"good", "bad"}},
		{Key: "note_required", Label: "Note", Type: FieldText, Required: false},
	}
}

func TestValidateValues_ok(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": 128.0, "mood": "good"})
	if err != nil {
		t.Fatalf("valid payload rejected: %v", err)
	}
}

func TestValidateValues_unknownKey(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": 128.0, "spo2": 97.0})
	if err == nil {
		t.Fatal("expected error for unknown key")
	}
}

func TestValidateValues_missingRequired(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"mood": "good"})
	if err == nil {
		t.Fatal("expected error for missing required systolic")
	}
}

func TestValidateValues_wrongType(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": "high"})
	if err == nil {
		t.Fatal("expected error for non-number systolic")
	}
}

func TestValidateValues_enumNotInOptions(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": 120.0, "mood": "meh"})
	if err == nil {
		t.Fatal("expected error for enum value not in options")
	}
}

func TestValidateValues_datetimeParsed(t *testing.T) {
	fields := []Field{{Key: "at", Label: "At", Type: FieldDatetime}}
	if err := ValidateValues(fields, map[string]any{"at": "2026-06-12T14:30:00Z"}); err != nil {
		t.Fatalf("valid RFC3339 rejected: %v", err)
	}
	if err := ValidateValues(fields, map[string]any{"at": "not-a-time"}); err == nil {
		t.Fatal("expected error for unparseable datetime")
	}
}

func TestBreaches(t *testing.T) {
	min120, max140 := 120.0, 140.0
	fields := []Field{
		{Key: "systolic", Type: FieldNumber, Threshold: &Threshold{Max: &max140}},
		{Key: "weight", Type: FieldNumber, Threshold: &Threshold{Min: &min120}},
		{Key: "pulse", Type: FieldNumber}, // no threshold -> never breaches
	}
	got := Breaches(fields, map[string]any{"systolic": 162.0, "weight": 110.0, "pulse": 999.0})
	if len(got) != 2 {
		t.Fatalf("expected 2 breaches, got %d: %+v", len(got), got)
	}
}
