package middleware

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/awslabs/aws-lambda-go-api-proxy/core"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type claims struct {
	Sub, Email, Name string
}

// Authenticator builds the AuthContext per request: verified claims → JIT user
// provisioning → membership load → AuthContext attached to the request context.
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
		if _, err := m.stores.Users.Get(ctx, c.Sub); errors.Is(err, store.ErrNotFound) {
			if _, cerr := m.stores.Users.CreateIfAbsent(ctx, domain.User{
				UserID: c.Sub, Email: email, Name: c.Name, CreatedAt: m.now().UTC(),
			}); cerr != nil {
				httpx.ServerError(w, r, cerr, "provisioning failed")
				return
			}
		} else if err != nil {
			httpx.ServerError(w, r, err, "auth load failed")
			return
		}

		ms, err := m.stores.Memberships.ListByUser(ctx, c.Sub)
		if err != nil {
			httpx.ServerError(w, r, err, "auth load failed")
			return
		}
		ac := &auth.AuthContext{UserID: c.Sub, Email: email, Memberships: make(map[string]domain.Role, len(ms))}
		for _, mem := range ms {
			ac.Memberships[mem.CareGroupID] = mem.Role
		}
		next.ServeHTTP(w, r.WithContext(auth.NewContext(ctx, ac)))
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
