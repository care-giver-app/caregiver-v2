// Package httpx holds shared HTTP response + permission helpers for handlers.
package httpx

import (
	"encoding/json"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
)

func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type errorBody struct {
	Message string `json:"message"`
}

func WriteError(w http.ResponseWriter, status int, msg string) {
	WriteJSON(w, status, errorBody{Message: msg})
}

// RequireMember writes 403 and returns false unless the caller is a member.
func RequireMember(w http.ResponseWriter, a *auth.AuthContext, careGroupID string) bool {
	if a == nil || !a.IsMember(careGroupID) {
		WriteError(w, http.StatusForbidden, "forbidden")
		return false
	}
	return true
}

// RequireAdmin writes 403 and returns false unless the caller is an admin.
func RequireAdmin(w http.ResponseWriter, a *auth.AuthContext, careGroupID string) bool {
	if a == nil || !a.IsAdmin(careGroupID) {
		WriteError(w, http.StatusForbidden, "forbidden")
		return false
	}
	return true
}
