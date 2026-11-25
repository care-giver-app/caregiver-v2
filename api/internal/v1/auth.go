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
	// EmailVerified is the token's email_verified claim as sent ("true" or
	// "false"), or empty when the token carries none.
	EmailVerified string
}

// caller is the signed-in caregiver, as resolved by the Authenticator.
type caller struct {
	UserID string
	Email  string // normalized; empty when the token carries none
	Name   string // from the user row, not the current token
	// EmailNotifications is the account's email channel, from the user row.
	EmailNotifications bool
	// Closed is set only on the one route that serves a closed account
	// (WrapClosing): finishing a close that stopped partway.
	Closed bool
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

// NewAuthenticator reads the claims API Gateway's JWT authorizer verified.
func NewAuthenticator(s *store.Stores) *Authenticator {
	return &Authenticator{stores: s, now: time.Now, extract: claimsFromRequest}
}

// NewBearerAuthenticator verifies the request's bearer token itself, for a
// route served without the API Gateway authorizer.
func NewBearerAuthenticator(s *store.Stores, v *TokenVerifier) *Authenticator {
	return &Authenticator{stores: s, now: time.Now, extract: v.claimsFromBearer}
}

// Wrap requires a signed-in caregiver with an open account.
func (m *Authenticator) Wrap(next http.Handler) http.Handler { return m.wrap(next, false) }

// WrapClosing is Wrap that also lets a closed account through, marked Closed.
// Only Close account is served this way: a close that removed the account's
// row but not its sign-in can then be finished by trying again.
func (m *Authenticator) WrapClosing(next http.Handler) http.Handler { return m.wrap(next, true) }

// WrapOptional serves a request without an Authorization header as nobody —
// no caller, and nothing about the caller added to the logger — and any other
// as Wrap does, so a token that is there but does not verify is a 401.
func (m *Authenticator) WrapOptional(next http.Handler) http.Handler {
	signedIn := m.wrap(next, false)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := m.extract(r); !ok && r.Header.Get("Authorization") == "" {
			next.ServeHTTP(w, r)
			return
		}
		signedIn.ServeHTTP(w, r)
	})
}

func (m *Authenticator) wrap(next http.Handler, allowClosed bool) http.Handler {
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
		closed := u.Status == domain.UserClosed
		if closed && !allowClosed {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		// The address follows the identity provider: Change email is confirmed
		// there, and the first request whose token carries the new address
		// copies it onto the row (ADR 0012, User, amended in the Settings
		// endpoints gate). Only a differing, verified address costs a write.
		if !closed && email != "" && email != u.Email && c.EmailVerified != "false" {
			if err := m.stores.Users.SetEmail(ctx, c.Sub, email); err != nil {
				// Not fatal: the next request tries again.
				logger.FromContext(ctx).Warn("email sync failed", "err", err)
			}
		}

		next.ServeHTTP(w, r.WithContext(withCaller(ctx, &caller{
			UserID: c.Sub, Email: email, Name: u.Name, EmailNotifications: u.EmailNotifications, Closed: closed,
		})))
	})
}

func claimsFromRequest(r *http.Request) (claims, bool) {
	reqCtx, ok := core.GetAPIGatewayV2ContextFromContext(r.Context())
	if !ok || reqCtx.Authorizer == nil || reqCtx.Authorizer.JWT == nil {
		return claims{}, false
	}
	cl := reqCtx.Authorizer.JWT.Claims
	return claims{Sub: cl["sub"], Email: cl["email"], Name: claimName(cl), EmailVerified: cl["email_verified"]}, true
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
