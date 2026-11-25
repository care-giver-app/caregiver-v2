package v1

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Account serves the caller's own account from Settings: name and email
// notifications, Change email, and Close account.
type Account struct {
	stores *store.Stores
	idp    IdentityProvider
	now    func() time.Time
}

func NewAccount(s *store.Stores, idp IdentityProvider) *Account {
	return &Account{stores: s, idp: idp, now: time.Now}
}

// MaxCaregiverNameLength is the longest name a caregiver may give
// themselves, in characters (ChangeMyAccountRequest).
const MaxCaregiverNameLength = 100

// Messages for the contract's named refusals.
const (
	msgWrongPassword   = "the password is not right"
	msgTooManyAttempts = "too many tries in a short time; try again later"
	msgEmailInUse      = "another account already uses that address"
	msgSoleAdmin       = "you are the only admin of these care teams; promote someone else first, or close a team you are alone on"
)

// Change serves PATCH /v1/me: the caller's name, and whether the app may
// reach them by email. Fields left out are unchanged.
func (h *Account) Change(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	var req struct {
		Name               *string `json:"name"`
		EmailNotifications *bool   `json:"email_notifications"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Name == nil && req.EmailNotifications == nil {
		httpx.WriteError(w, http.StatusBadRequest, "name or email_notifications is required")
		return
	}
	change := store.UserChange{EmailNotifications: req.EmailNotifications}
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if n := utf8.RuneCountInString(name); n < 1 || n > MaxCaregiverNameLength {
			httpx.WriteError(w, http.StatusBadRequest, "name must be 1-100 characters")
			return
		}
		change.Name = &name
	}
	u, err := h.stores.Users.Update(r.Context(), c.UserID, change)
	if errors.Is(err, store.ErrNotFound) {
		// Closed between the authenticator's read and this write.
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	// The address is the token's, which the authenticator has just copied
	// onto the row if it differed.
	httpx.WriteJSON(w, http.StatusOK, caregiverView{
		UserID: u.UserID, Email: c.Email, Name: u.Name, EmailNotifications: u.EmailNotifications,
	})
}

// signIn is what the caller signs in with: their address, or their user id
// (also their identity-provider username) when the token carries none.
func signIn(c *caller) string {
	if c.Email != "" {
		return c.Email
	}
	return c.UserID
}

// checkPassword writes the refusal and returns false when the password is not
// the caller's.
func (h *Account) checkPassword(w http.ResponseWriter, r *http.Request, c *caller, password string) bool {
	switch err := h.idp.CheckPassword(r.Context(), signIn(c), password); {
	case err == nil:
		return true
	case errors.Is(err, ErrWrongPassword):
		httpx.WriteError(w, http.StatusForbidden, msgWrongPassword)
	case errors.Is(err, ErrTooManyAttempts):
		httpx.WriteError(w, http.StatusTooManyRequests, msgTooManyAttempts)
	default:
		httpx.ServerError(w, r, err, "password check failed")
	}
	return false
}

// StartEmailChange serves POST /v1/me/email: with the current password, the
// new address is sent a code. Nothing changes here until the code is
// confirmed against the identity provider; the authenticator then copies the
// new address onto the row from the first token that carries it.
func (h *Account) StartEmailChange(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	var req struct {
		CurrentPassword string `json:"current_password"`
		NewEmail        string `json:"new_email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.CurrentPassword == "" {
		httpx.WriteError(w, http.StatusBadRequest, "current_password is required")
		return
	}
	email, err := domain.ValidateInviteEmail(req.NewEmail)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	if email == c.Email {
		httpx.WriteError(w, http.StatusBadRequest, "that is already this account's address")
		return
	}
	if !h.checkPassword(w, r, c, req.CurrentPassword) {
		return
	}
	// The identity provider is what refuses an address in use; this read
	// only answers sooner, and without sending a code, for one a caregiver
	// row already holds.
	ids, err := h.stores.Users.IDsByEmail(r.Context(), email)
	if err != nil {
		httpx.ServerError(w, r, err, "email check failed")
		return
	}
	for _, id := range ids {
		if id != c.UserID {
			httpx.WriteError(w, http.StatusConflict, msgEmailInUse)
			return
		}
	}
	switch err := h.idp.StartEmailChange(r.Context(), c.UserID, email); {
	case err == nil:
	case errors.Is(err, ErrEmailInUse):
		httpx.WriteError(w, http.StatusConflict, msgEmailInUse)
		return
	case errors.Is(err, ErrTooManyAttempts):
		httpx.WriteError(w, http.StatusTooManyRequests, msgTooManyAttempts)
		return
	default:
		httpx.ServerError(w, r, err, "email change failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// soleAdminOf is the SoleAdminOf schema.
type soleAdminOf struct {
	Message string          `json:"message"`
	Teams   []soleAdminTeam `json:"teams"`
}

// soleAdminTeam is the SoleAdminTeam schema. Alone means nobody else is on the
// team, so there is nobody to promote and it has to be closed first.
type soleAdminTeam struct {
	TeamID string `json:"team_id"`
	Name   string `json:"name"`
	Alone  bool   `json:"alone"`
}

// Close serves POST /v1/me/close: with the password, the account is closed.
// Each team is left as leaving leaves it, the row keeps only what makes the
// care it recorded read as a former caregiver's, and the identity-provider
// user is deleted so the address can sign up again as a new account.
//
// Refused, naming every such team, while the caller is any active team's only
// admin — including a team they are alone on, whose only admin they are too.
//
// The steps run in this order so that a close stopped partway can always be
// finished by sending it again:
//
//  1. Leave each team. Each removal stands on its own and an already-removed
//     membership is skipped, so a retry carries on where this stopped.
//  2. Close the row. From here the account reads as a former caregiver's
//     everywhere, even if the last step fails.
//  3. Delete the identity-provider user. Until this succeeds the caregiver
//     can still sign in, and this route alone (WrapClosing) still serves the
//     closed account, so sending it again finishes the job. Deleting first
//     would have been the other way round: a failure after it would leave a
//     name and address on the row with no way left to sign in and remove them.
func (h *Account) Close(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	var req struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Password == "" {
		httpx.WriteError(w, http.StatusBadRequest, "password is required")
		return
	}
	if !h.checkPassword(w, r, c, req.Password) {
		return
	}
	ctx := r.Context()
	if !c.Closed {
		sole, err := h.stores.SoleAdminOf(ctx, c.UserID)
		if err != nil {
			httpx.ServerError(w, r, err, "team load failed")
			return
		}
		if len(sole) > 0 {
			h.writeSoleAdmin(w, r, sole)
			return
		}
		if !h.leaveEveryTeam(w, r, c) {
			return
		}
		if err := h.stores.Users.Close(ctx, c.UserID, h.now().UTC()); err != nil {
			httpx.ServerError(w, r, err, "close failed")
			return
		}
	}
	if err := h.idp.DeleteUser(ctx, c.UserID); err != nil {
		httpx.ServerError(w, r, err, "sign-in removal failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// leaveEveryTeam removes each of the caller's memberships the way leaving
// does: their assignments still ahead go and any coverage schedule naming
// them ends today (Stores.RemoveMember).
func (h *Account) leaveEveryTeam(w http.ResponseWriter, r *http.Request, c *caller) bool {
	ctx := r.Context()
	ms, err := h.stores.Memberships.ListByUser(ctx, c.UserID)
	if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return false
	}
	now := h.now().UTC()
	for _, m := range ms {
		switch err := h.stores.RemoveMember(ctx, m.TeamID, c.UserID, now); {
		case err == nil, errors.Is(err, store.ErrNotFound):
		case errors.Is(err, store.ErrLastAdmin):
			// The team's other admin stepped down or went since the check.
			team, terr := h.stores.Teams.Get(ctx, m.TeamID)
			if terr != nil {
				httpx.ServerError(w, r, terr, "team load failed")
				return false
			}
			h.writeSoleAdmin(w, r, []domain.Team{team})
			return false
		default:
			httpx.ServerError(w, r, err, "leaving a team failed", "team_id", m.TeamID)
			return false
		}
	}
	return true
}

func (h *Account) writeSoleAdmin(w http.ResponseWriter, r *http.Request, teams []domain.Team) {
	refs := make([]soleAdminTeam, 0, len(teams))
	for _, t := range teams {
		members, err := h.stores.Memberships.ListByTeam(r.Context(), t.TeamID)
		if err != nil {
			httpx.ServerError(w, r, err, "team load failed", "team_id", t.TeamID)
			return
		}
		refs = append(refs, soleAdminTeam{TeamID: t.TeamID, Name: t.Name, Alone: len(members) <= 1})
	}
	httpx.WriteJSON(w, http.StatusConflict, soleAdminOf{Message: msgSoleAdmin, Teams: refs})
}
