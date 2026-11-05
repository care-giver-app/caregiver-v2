package domain

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func TestRole_Valid(t *testing.T) {
	if !RoleAdmin.Valid() || !RoleCaregiver.Valid() {
		t.Fatal("admin/caregiver should be valid")
	}
	if Role("owner").Valid() || Role("").Valid() {
		t.Fatal("owner/empty should be invalid")
	}
}

func TestNormalizeEmail(t *testing.T) {
	if got := NormalizeEmail("  Foo@Bar.COM "); got != "foo@bar.com" {
		t.Fatalf("got %q", got)
	}
}

func TestValidateTeamName(t *testing.T) {
	cases := []struct {
		name, in, want string
		ok             bool
	}{
		{"trims", "  The Amins \t\n", "The Amins", true},
		{"empty", "", "", false},
		{"whitespace only", "   \t ", "", false},
		{"100 runes", strings.Repeat("a", 100), strings.Repeat("a", 100), true},
		{"101 runes", strings.Repeat("a", 101), "", false},
		{"100 multibyte runes", strings.Repeat("é", 100), strings.Repeat("é", 100), true},
		{"101 multibyte runes", strings.Repeat("é", 101), "", false},
		{"100 runes after trim", " " + strings.Repeat("家", 100) + " ", strings.Repeat("家", 100), true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := ValidateTeamName(c.in)
			if c.ok {
				if err != nil || got != c.want {
					t.Fatalf("got %q err=%v, want %q", got, err, c.want)
				}
				return
			}
			if !errors.Is(err, ErrInvalidTeamName) {
				t.Fatalf("want ErrInvalidTeamName, got %q err=%v", got, err)
			}
		})
	}
}

func TestInvitation_Expired(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	cases := []struct {
		name    string
		expires int64
		want    bool
	}{
		{"future", now.Unix() + 1, false},
		{"exactly now", now.Unix(), true},
		{"past", now.Unix() - 1, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := (Invitation{ExpiresAt: c.expires}).Expired(now); got != c.want {
				t.Fatalf("Expired = %v, want %v", got, c.want)
			}
		})
	}
}

func TestNewMembership_defaults(t *testing.T) {
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)
	m := NewMembership("u1", "t1", RoleCaregiver, now)
	if m.UserID != "u1" || m.TeamID != "t1" || m.Role != RoleCaregiver || !m.JoinedAt.Equal(now) {
		t.Fatalf("unexpected: %+v", m)
	}
	if !m.NotifyReminders || !m.NotifyRangeAlerts || !m.NotifyGapAlerts || !m.NotifyUnrecordedAlerts {
		t.Fatalf("every notify_* should default on: %+v", m)
	}
}
