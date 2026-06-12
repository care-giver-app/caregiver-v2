package domain

import (
	"testing"
	"time"
)

func TestNewInviteToken_isRandomAndURLSafe(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 100; i++ {
		tok, err := NewInviteToken()
		if err != nil {
			t.Fatalf("NewInviteToken: %v", err)
		}
		if len(tok) < 20 {
			t.Fatalf("token too short: %q", tok)
		}
		for _, r := range tok {
			if !(r == '-' || r == '_' || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')) {
				t.Fatalf("token not URL-safe: %q", tok)
			}
		}
		if seen[tok] {
			t.Fatalf("duplicate token: %q", tok)
		}
		seen[tok] = true
	}
}

func TestRole_Valid(t *testing.T) {
	if !RoleAdmin.Valid() || !RoleCaregiver.Valid() {
		t.Fatal("admin/caregiver should be valid")
	}
	if Role("owner").Valid() {
		t.Fatal("owner should be invalid")
	}
}

func TestNormalizeEmail(t *testing.T) {
	if got := NormalizeEmail("  Foo@Bar.COM "); got != "foo@bar.com" {
		t.Fatalf("got %q", got)
	}
}

func TestInvitation_Expired(t *testing.T) {
	now := time.Unix(1000, 0)
	if (Invitation{ExpiresAt: 1001}).Expired(now) {
		t.Fatal("not expired yet")
	}
	if !(Invitation{ExpiresAt: 1000}).Expired(now) {
		t.Fatal("should be expired at boundary")
	}
}
