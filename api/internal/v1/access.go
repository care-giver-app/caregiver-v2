package v1

import (
	"errors"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// requireTeamRole writes 403 and returns false unless the caller belongs to
// the team, and is its admin when admin is true. The team comes from the row
// being read or written, never from the request.
func requireTeamRole(w http.ResponseWriter, r *http.Request, s *store.Stores, c *caller, teamID string, admin bool) bool {
	m, err := s.Memberships.Get(r.Context(), c.UserID, teamID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden")
		return false
	} else if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return false
	}
	if admin && m.Role != domain.RoleAdmin {
		httpx.WriteError(w, http.StatusForbidden, "forbidden")
		return false
	}
	return true
}

// loadReceiver writes 404 and returns false when the receiver is unknown or
// archived.
func loadReceiver(w http.ResponseWriter, r *http.Request, s *store.Stores, receiverID string) (domain.Receiver, bool) {
	rc, err := s.Receivers.Get(r.Context(), receiverID)
	if errors.Is(err, store.ErrNotFound) || (err == nil && rc.Status == domain.ReceiverArchived) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return domain.Receiver{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "receiver load failed")
		return domain.Receiver{}, false
	}
	return rc, true
}

// loadTracker writes 404 and returns false when the tracker is unknown or its
// receiver is unknown or archived.
func loadTracker(w http.ResponseWriter, r *http.Request, s *store.Stores, trackerID string) (domain.Tracker, domain.Receiver, bool) {
	t, err := s.Trackers.Get(r.Context(), trackerID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return domain.Tracker{}, domain.Receiver{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return domain.Tracker{}, domain.Receiver{}, false
	}
	rc, ok := loadReceiver(w, r, s, t.ReceiverID)
	if !ok {
		return domain.Tracker{}, domain.Receiver{}, false
	}
	return t, rc, true
}
