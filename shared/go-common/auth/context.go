// Package auth holds the authenticated caller's identity + authorization state.
// It is HTTP-free so every backend phase can reuse it.
package auth

import (
	"context"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

// AuthContext is the caller's identity plus their care-group memberships.
type AuthContext struct {
	UserID      string
	Email       string
	Memberships map[string]domain.Role // care_group_id -> role
}

func (a AuthContext) RoleIn(careGroupID string) (domain.Role, bool) {
	r, ok := a.Memberships[careGroupID]
	return r, ok
}

func (a AuthContext) IsMember(careGroupID string) bool {
	_, ok := a.Memberships[careGroupID]
	return ok
}

func (a AuthContext) IsAdmin(careGroupID string) bool {
	r, ok := a.Memberships[careGroupID]
	return ok && r == domain.RoleAdmin
}

type ctxKey struct{}

func NewContext(ctx context.Context, a *AuthContext) context.Context {
	return context.WithValue(ctx, ctxKey{}, a)
}

func FromContext(ctx context.Context) *AuthContext {
	a, _ := ctx.Value(ctxKey{}).(*AuthContext)
	return a
}
