package auth

import (
	"context"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func ctxWith() *AuthContext {
	return &AuthContext{
		UserID: "u1", Email: "u1@x.com",
		Memberships: map[string]domain.Role{"g1": domain.RoleAdmin, "g2": domain.RoleCaregiver},
	}
}

func TestPredicates(t *testing.T) {
	a := ctxWith()
	if !a.IsMember("g1") || !a.IsMember("g2") || a.IsMember("g3") {
		t.Fatal("IsMember")
	}
	if !a.IsAdmin("g1") || a.IsAdmin("g2") || a.IsAdmin("g3") {
		t.Fatal("IsAdmin")
	}
	if r, ok := a.RoleIn("g2"); !ok || r != domain.RoleCaregiver {
		t.Fatalf("RoleIn g2: %v %v", r, ok)
	}
}

func TestContextRoundTrip(t *testing.T) {
	a := ctxWith()
	ctx := NewContext(context.Background(), a)
	if FromContext(ctx) != a {
		t.Fatal("round trip")
	}
	if FromContext(context.Background()) != nil {
		t.Fatal("absent should be nil")
	}
}
