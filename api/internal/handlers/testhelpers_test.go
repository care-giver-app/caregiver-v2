package handlers_test

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func withAuth(r *http.Request, userID, email string, memberships map[string]domain.Role) *http.Request {
	if memberships == nil {
		memberships = map[string]domain.Role{}
	}
	ac := &auth.AuthContext{UserID: userID, Email: email, Memberships: memberships}
	return r.WithContext(auth.NewContext(r.Context(), ac))
}
