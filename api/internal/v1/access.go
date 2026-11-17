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
	_, ok := requireMembership(w, r, s, c, teamID, admin)
	return ok
}

// requireMembership is requireTeamRole, also returning the caller's
// membership.
func requireMembership(w http.ResponseWriter, r *http.Request, s *store.Stores, c *caller, teamID string, admin bool) (domain.Membership, bool) {
	m, err := s.Memberships.Get(r.Context(), c.UserID, teamID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden")
		return domain.Membership{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return domain.Membership{}, false
	}
	if admin && m.Role != domain.RoleAdmin {
		httpx.WriteError(w, http.StatusForbidden, "forbidden")
		return domain.Membership{}, false
	}
	return m, true
}

// loadTeam writes 404 and returns false when the team is unknown or archived
// (closed), the way listing a team's receivers always has.
func loadTeam(w http.ResponseWriter, r *http.Request, s *store.Stores, teamID string) (domain.Team, bool) {
	team, err := s.Teams.Get(r.Context(), teamID)
	if errors.Is(err, store.ErrNotFound) || (err == nil && team.Status == domain.TeamArchived) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return domain.Team{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "team load failed")
		return domain.Team{}, false
	}
	return team, true
}

// loadAnyReceiver writes 404 and returns false when the receiver is unknown.
// Unlike loadReceiver it returns an archived one: the Team area reads them,
// and refuses changes to them with 409 rather than 404.
func loadAnyReceiver(w http.ResponseWriter, r *http.Request, s *store.Stores, receiverID string) (domain.Receiver, bool) {
	rc, err := s.Receivers.Get(r.Context(), receiverID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return domain.Receiver{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "receiver load failed")
		return domain.Receiver{}, false
	}
	return rc, true
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
