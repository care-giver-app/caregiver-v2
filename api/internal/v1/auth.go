// Package v1 holds the /v1 HTTP surface: the authenticator and handlers that
// read and write only the v1 tables (docs/adr/0012-*, 0013-*). It sits beside
// the old middleware and handlers packages until cutover, and imports nothing
// from them, so either side can be deleted wholesale.
package v1

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/awslabs/aws-lambda-go-api-proxy/core"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

type claims struct {
	Sub, Email, Name string
}

// caller is the signed-in caregiver, as resolved by the Authenticator.
type caller struct {
	UserID string
	Email  string // normalized; empty when the token carries none
	Name   string // from the user row, not the current token
}

type callerKey struct{}

func withCaller(ctx context.Context, c *caller) context.Context {
	return context.WithValue(ctx, callerKey{}, c)
}

func callerFrom(ctx context.Context) *caller {
	c, _ := ctx.Value(callerKey{}).(*caller)
	return c
}

// Authenticator resolves the caller per request: verified claims → read-first
// JIT provisioning of the v1 user row → caller attached to the request context.
// Memberships are not preloaded; handlers read what they need.
type Authenticator struct {
	stores  *store.Stores
	now     func() time.Time
	extract func(*http.Request) (claims, bool)
}

func NewAuthenticator(s *store.Stores) *Authenticator {
	return &Authenticator{stores: s, now: time.Now, extract: claimsFromRequest}
}

func (m *Authenticator) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, ok := m.extract(r)
		if !ok || c.Sub == "" {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		ctx := logger.NewContext(r.Context(), logger.FromContext(r.Context()).With("user_id", c.Sub))
		r = r.WithContext(ctx)
		email := domain.NormalizeEmail(c.Email)

		// Read-first: only write on a user's first request, so the steady-state
		// hot path is a read rather than a conditional write that always fails.
		u, err := m.stores.Users.Get(ctx, c.Sub)
		if errors.Is(err, store.ErrNotFound) {
			u = domain.User{
				UserID: c.Sub, Email: email, Name: c.Name, EmailNotifications: true,
				Status: domain.UserActive, CreatedAt: m.now().UTC(),
			}
			created, cerr := m.stores.Users.CreateIfAbsent(ctx, u)
			if cerr != nil {
				httpx.ServerError(w, r, cerr, "provisioning failed")
				return
			}
			if !created {
				// A concurrent first request won the write; use its row.
				if u, err = m.stores.Users.Get(ctx, c.Sub); err != nil {
					httpx.ServerError(w, r, err, "auth load failed")
					return
				}
			}
		} else if err != nil {
			httpx.ServerError(w, r, err, "auth load failed")
			return
		}
		// A closed account is never silently reused.
		if u.Status == domain.UserClosed {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
			return
		}

		next.ServeHTTP(w, r.WithContext(withCaller(ctx, &caller{UserID: c.Sub, Email: email, Name: u.Name})))
	})
}

func claimsFromRequest(r *http.Request) (claims, bool) {
	reqCtx, ok := core.GetAPIGatewayV2ContextFromContext(r.Context())
	if !ok || reqCtx.Authorizer == nil || reqCtx.Authorizer.JWT == nil {
		return claims{}, false
	}
	cl := reqCtx.Authorizer.JWT.Claims
	return claims{Sub: cl["sub"], Email: cl["email"], Name: claimName(cl)}, true
}

func claimName(cl map[string]string) string {
	if n := cl["name"]; n != "" {
		return n
	}
	gn, fn := cl["given_name"], cl["family_name"]
	return strings.TrimSpace(gn + " " + fn)
}

// requireCaller writes 401 and returns nil when no caller is attached, which
// only happens if a handler is mounted without the Authenticator.
func requireCaller(w http.ResponseWriter, r *http.Request) *caller {
	c := callerFrom(r.Context())
	if c == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
	}
	return c
}

// teamMembership is the TeamMembership schema.
type teamMembership struct {
	TeamID string `json:"team_id"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}
