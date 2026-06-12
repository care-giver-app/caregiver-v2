package domain

import "testing"

func TestTrackerKind_Valid(t *testing.T) {
	for _, k := range []TrackerKind{KindEvent, KindMeasurement, KindScheduled} {
		if !k.Valid() {
			t.Fatalf("%q should be valid", k)
		}
	}
	if TrackerKind("custom").Valid() {
		t.Fatal("custom should be invalid")
	}
	if TrackerKind("event_with_note").Valid() {
		t.Fatal("event_with_note was dropped and must be invalid")
	}
}

func TestFieldType_Valid(t *testing.T) {
	for _, ft := range []FieldType{FieldNumber, FieldText, FieldBoolean, FieldEnum, FieldDatetime} {
		if !ft.Valid() {
			t.Fatalf("%q should be valid", ft)
		}
	}
	if FieldType("currency").Valid() {
		t.Fatal("currency should be invalid")
	}
}
