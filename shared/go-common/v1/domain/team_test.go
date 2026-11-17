package domain

import (
	"errors"
	"strings"
	"testing"
)

func TestValidateTimeZone(t *testing.T) {
	for _, ok := range []string{"America/Chicago", "UTC", "Europe/London", " Asia/Tokyo "} {
		if _, err := ValidateTimeZone(ok); err != nil {
			t.Errorf("%q: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "Local", "Mars/Olympus", "  "} {
		if _, err := ValidateTimeZone(bad); !errors.Is(err, ErrInvalidTimeZone) {
			t.Errorf("%q accepted", bad)
		}
	}
}

func TestValidateInviteEmail(t *testing.T) {
	if got, err := ValidateInviteEmail("  Sam@Example.COM "); err != nil || got != "sam@example.com" {
		t.Fatalf("got %q %v", got, err)
	}
	for _, bad := range []string{"", "nope", "Sam <sam@x.com>", strings.Repeat("a", 250) + "@x.com"} {
		if _, err := ValidateInviteEmail(bad); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}

func TestValidateCareInstructions(t *testing.T) {
	if b, err := ValidateCareInstructions("  \n "); err != nil || b != "" {
		t.Fatalf("blank: %q %v", b, err)
	}
	if b, err := ValidateCareInstructions(" Pills \n"); err != nil || b != " Pills \n" {
		t.Fatalf("kept as written: %q %v", b, err)
	}
	if _, err := ValidateCareInstructions(strings.Repeat("é", 20000)); err != nil {
		t.Fatalf("20000 runes: %v", err)
	}
	if _, err := ValidateCareInstructions(strings.Repeat("é", 20001)); err == nil {
		t.Fatal("20001 accepted")
	}
}

func TestResolveContacts(t *testing.T) {
	existing := []EmergencyContact{{ContactID: "c1", Name: "Dr", Phone: "1"}}
	n := 0
	newID := func() string { n++; return "new" + string(rune('0'+n)) }
	got, err := ResolveContacts([]ContactWrite{
		{Name: " Sam ", Relationship: "Son", Phone: " 555 "},
		{ContactID: "c1", Name: "Dr Lee", Phone: "556"},
	}, existing, newID)
	if err != nil || len(got) != 2 || got[0] != (EmergencyContact{ContactID: "new1", Name: "Sam", Relationship: "Son", Phone: "555"}) ||
		got[1].ContactID != "c1" || got[1].Name != "Dr Lee" {
		t.Fatalf("got %+v %v", got, err)
	}
	if _, err := ResolveContacts([]ContactWrite{{ContactID: "zz", Name: "x", Phone: "1"}}, existing, newID); !errors.Is(err, ErrUnknownContact) {
		t.Fatalf("unknown id: %v", err)
	}
	for name, in := range map[string][]ContactWrite{
		"twice":      {{ContactID: "c1", Name: "a", Phone: "1"}, {ContactID: "c1", Name: "b", Phone: "2"}},
		"no name":    {{Name: " ", Phone: "1"}},
		"no phone":   {{Name: "a"}},
		"long phone": {{Name: "a", Phone: strings.Repeat("1", 41)}},
		"too many":   make([]ContactWrite, 21),
	} {
		if _, err := ResolveContacts(in, existing, newID); err == nil {
			t.Errorf("%s accepted", name)
		}
	}
	if got, err := ResolveContacts(nil, existing, newID); err != nil || len(got) != 0 {
		t.Fatalf("empty list: %+v %v", got, err)
	}
}
