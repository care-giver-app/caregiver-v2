// Package httpx holds shared HTTP response + permission helpers for handlers.
package httpx

import (
	"encoding/json"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
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

// ServerError logs the underlying err (plus any extra structured attrs) at Error
// using the request-scoped logger, then writes the generic 500 response. The
// client never sees err — only msg. Use this at every server-error site that has
// an error in scope; keep WriteError for 4xx client errors.
func ServerError(w http.ResponseWriter, r *http.Request, err error, msg string, attrs ...any) {
	errStr := ""
	if err != nil {
		errStr = err.Error()
	}
	args := append([]any{"err", errStr, "client_msg", msg}, attrs...)
	logger.FromContext(r.Context()).Error("server error", args...)
	WriteError(w, http.StatusInternalServerError, msg)
}

// RequireAdmin writes 403 and returns false unless the caller is an admin.
func RequireAdmin(w http.ResponseWriter, a *auth.AuthContext, careGroupID string) bool {
	if a == nil || !a.IsAdmin(careGroupID) {
		WriteError(w, http.StatusForbidden, "forbidden")
		return false
	}
	return true
}
